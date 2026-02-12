# LXC_monitoring Profile Configuration
# Centralized monitoring server with Grafana + Prometheus
# Scrapes metrics from all LXC containers
#
# Extends LXC-base-config.nix with monitoring stack

let
  base = import ./LXC-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "monitoring";
    profile = "proxmox-lxc";
    envProfile = "LXC_monitoring"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_monitoring -s -u";
    serverEnv = "PROD"; # Production environment

    # Network - LXC uses Proxmox-managed networking
    ipAddress = "192.168.8.85";
    nameServers = [ "192.168.8.1" ];
    resolvedEnable = true;

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP (redirect to HTTPS)
      443   # HTTPS (nginx)
      3002  # Grafana (internal)
      9090  # Prometheus (internal)
    ];
    allowedUDPPorts = [ ];

    # System packages (extends base with monitoring-specific packages)
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.curl # For healthchecks
        # Note: vim, wget, zsh, git, git-crypt, rclone, btop, fzf, tldr, home-manager, jq, python3 already in base
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Monitoring Stack (enabled - this IS the monitoring server) ===
    grafanaEnable = true;

    # === Prometheus Exporters (DISABLED - this is the server, not a target) ===
    # The monitoring server has its own local exporters configured in grafana.nix
    prometheusExporterEnable = false;
    prometheusExporterCadvisorEnable = false;

    # === Remote Targets for Prometheus Scraping ===
    prometheusRemoteTargets = [
      { name = "lxc_home";       host = "192.168.8.80";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_proxy";      host = "192.168.8.102"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_plane";      host = "192.168.8.86";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_liftcraft";  host = "192.168.8.87";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_portfolio";  host = "192.168.8.88";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_mailer";     host = "192.168.8.89";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_database";   host = "192.168.8.103"; nodePort = 9100; cadvisorPort = null; }  # Centralized database server (no Docker)
      { name = "lxc_matrix";     host = "192.168.8.104"; nodePort = 9100; cadvisorPort = 9092; }  # Matrix Synapse + Element + Claude Bot
      { name = "lxc_tailscale";  host = "192.168.8.105"; nodePort = 9100; cadvisorPort = null; }  # Tailscale subnet router (no Docker)
      { name = "vps_wireguard";  host = "172.26.5.155";  nodePort = 9100; cadvisorPort = null; }  # VPS via WireGuard tunnel
    ];

    # === Application Metrics (Exportarr for *arr stack + Database exporters) ===
    prometheusAppTargets = [
      { name = "sonarr";     host = "192.168.8.80";  port = 9707; }
      { name = "radarr";     host = "192.168.8.80";  port = 9708; }
      { name = "prowlarr";   host = "192.168.8.80";  port = 9709; }
      { name = "bazarr";     host = "192.168.8.80";  port = 9710; }
      # Centralized database exporters (LXC_database)
      { name = "postgresql"; host = "192.168.8.103"; port = 9187; }
      { name = "mariadb";    host = "192.168.8.103"; port = 9104; }
      { name = "redis";      host = "192.168.8.103"; port = 9121; }
      # Matrix Synapse metrics (LXC_matrix)
      { name = "synapse";    host = "192.168.8.104"; port = 9000; }
    ];

    # === Blackbox Exporter (HTTP/HTTPS and ICMP probes) ===
    prometheusBlackboxEnable = true;

    prometheusBlackboxHttpTargets = [
      # Local services - direct access within LAN
      # These are reliable checks - if local is up, global (via Cloudflare) works too
      { name = "jellyfin"; url = "https://jellyfin.${secrets.localDomain}"; }
      { name = "jellyseerr"; url = "https://jellyseerr.${secrets.localDomain}"; }
      { name = "nextcloud"; url = "https://nextcloud.${secrets.localDomain}"; }
      { name = "radarr"; url = "https://radarr.${secrets.localDomain}"; }
      { name = "sonarr"; url = "https://sonarr.${secrets.localDomain}"; }
      { name = "bazarr"; url = "https://bazarr.${secrets.localDomain}"; }
      { name = "prowlarr"; url = "https://prowlarr.${secrets.localDomain}"; }
      { name = "syncthing"; url = "https://syncthing.${secrets.localDomain}"; }
      { name = "calibre"; url = "https://books.${secrets.localDomain}"; }
      { name = "emulators"; url = "https://emulators.${secrets.localDomain}"; }
      { name = "unifi"; url = "https://192.168.8.206:8443/"; }
      { name = "grafana"; url = "https://grafana.${secrets.wildcardLocal}"; }
      { name = "prometheus"; url = "https://prometheus.${secrets.wildcardLocal}"; }

      # Services only accessible via Cloudflare (no local equivalent)
      { name = "plane"; url = "https://plane.${secrets.publicDomain}"; }
      { name = "leftyworkout_test"; url = "https://leftyworkout-test.${secrets.publicDomain}"; }
      { name = "portfolio"; url = "https://${secrets.publicDomain}"; }
      { name = "wgui"; url = "https://wgui.${secrets.publicDomain}"; }

      # Matrix/Element (local and public)
      { name = "matrix"; url = "https://matrix.${secrets.localDomain}/_matrix/client/versions"; }
      { name = "element"; url = "https://element.${secrets.localDomain}"; }

      # Local-only (no SSL)
      { name = "kuma"; url = "http://192.168.8.89:3001"; module = "http_2xx_nossl"; }
    ];

    prometheusBlackboxIcmpTargets = [
      # Infrastructure latency monitoring (ordered for dashboard display)
      { name = "wireguard_tunnel"; host = "172.26.5.155"; }   # VPS WireGuard tunnel
      { name = "tailscale"; host = "192.168.8.105"; }         # Tailscale subnet router
      { name = "wan"; host = "1.1.1.1"; }                     # WAN latency (Cloudflare DNS)
      { name = "pfsense"; host = "192.168.8.1"; }             # pfSense router
      { name = "switch_usw_aggr"; host = "192.168.8.180"; }   # UniFi Aggregation Switch
      { name = "switch_usw_24"; host = "192.168.8.181"; }     # UniFi 24-port Switch
      { name = "pve"; host = "192.168.8.82"; }                # Proxmox VE host
      { name = "lan_wifi"; host = "192.168.8.2"; }            # LAN WiFi AP
      { name = "guest_wifi"; host = "192.168.9.2"; }          # Guest WiFi AP
    ];

    # === TLS Certificate Expiry Monitoring ===
    # Certificate expiry is already monitored via HTTP probes (probe_ssl_earliest_cert_expiry)
    # No dedicated TLS targets needed - they were redundant with HTTP checks
    prometheusBlackboxTlsTargets = [];

    # === PVE Exporter (Proxmox metrics) ===
    prometheusPveExporterEnable = true;
    prometheusPveHost = "192.168.8.82";
    prometheusPveUser = "prometheus@pve";
    prometheusPveTokenName = "prometheus";
    prometheusPveTokenFile = "/etc/secrets/pve-token";

    # === PVE Backup Monitoring (queries Proxmox API for backup status) ===
    prometheusPveBackupEnable = true;

    # === pfSense Backup Monitoring (checks backup files on Proxmox NFS) ===
    prometheusPfsenseBackupEnable = true;
    prometheusPfsenseBackupProxmoxHost = "192.168.8.82";
    prometheusPfsenseBackupPath = "/mnt/pve/proxmox_backups/pfsense";

    # === TrueNAS Backup Monitoring (checks ZFS replication snapshots via SSH) ===
    prometheusTruenasBackupEnable = true;

    # === SNMP Exporter (pfSense) ===
    prometheusSnmpExporterEnable = true;
    # SNMPv3 credentials (preferred - requires NET-SNMP package on pfSense)
    prometheusSnmpv3User = secrets.snmpv3User;
    prometheusSnmpv3AuthPass = secrets.snmpv3AuthPass;
    prometheusSnmpv3PrivPass = secrets.snmpv3PrivPass;
    # SNMPv2c fallback (keep for transition period)
    prometheusSnmpCommunity = secrets.snmpCommunity;
    prometheusSnmpTargets = [
      { name = "pfsense"; host = "192.168.8.1"; module = "pfsense"; }
    ];

    # === Graphite Exporter (TrueNAS) ===
    # TrueNAS pushes Graphite metrics to this exporter
    # Configure TrueNAS: Destination IP: 192.168.8.85, Port: 2003
    prometheusGraphiteEnable = true;
    prometheusGraphitePort = 9109;       # Prometheus scrape port
    prometheusGraphiteInputPort = 2003;  # Graphite input from TrueNAS

    # === Package Modules ===
    systemBasicToolsEnable = false; # Minimal server - packages defined above
    systemNetworkToolsEnable = false;

    # === Shell Features ===
    atuinAutoSync = false;

    # === System Services & Features (ALL DISABLED - Monitoring Server) ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    starCitizenModules = false;

    # Optimizations
    havegedEnable = false; # Redundant on modern kernels
    fail2banEnable = false; # Behind firewall, nginx protected with basic auth

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:00)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:00:00";
    autoUpgradeRestartDocker = false; # No Docker stacks on monitoring server
    autoUserUpdateBranch = "release-25.11";

    # ============================================================================
    # EMAIL NOTIFICATIONS (Auto-update failure alerts)
    # ============================================================================
    notificationOnFailureEnable = true;
    notificationSmtpHost = "192.168.8.89";
    notificationSmtpPort = 25;
    notificationSmtpAuth = false;
    notificationSmtpTls = false;
    notificationFromEmail = secrets.notificationFrom;
    notificationToEmail = secrets.alertEmail;

    # ============================================================================
    # HOMELAB DOCKER STACKS (Disabled - no Docker stacks on monitoring server)
    # ============================================================================
    homelabDockerEnable = false;

    systemStable = true;
  };

  userSettings = base.userSettings // {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";

    extraGroups = [
      "wheel"
    ];

    theme = "io";
    wm = "none"; # Headless server
    wmEnableHyprland = false;

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "";
    defaultRoamDir = "Personal.p";
    term = "";
    font = "";

    dockerEnable = false; # No Docker needed on monitoring server
    virtualizationEnable = false;
    qemuGuestAddition = false;

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.git
      pkgs-unstable.claude-code
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) - ALL DISABLED (Headless Server) ===
    userBasicPkgsEnable = false;
    userAiPkgsEnable = false;

    # === Shell Customization ===
    starshipHostStyle = "bold #00FF00"; # Green for monitoring server

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Ensure proper terminal type for colors and cursor visibility
      export TERM=''${TERM:-xterm-256color}
      export COLORTERM=truecolor

      PROMPT=" ◉ %U%F{green}%n%f%u@%U%F{green}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
    '';
  };
}
