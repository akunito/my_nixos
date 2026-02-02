# LXC_monitoring Profile Configuration
# Centralized monitoring server with Grafana + Prometheus
# Scrapes metrics from all LXC containers
#
# Extends LXC-base-config.nix with monitoring stack

let
  base = import ./LXC-base-config.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "monitoring";
    profile = "proxmox-lxc";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_monitoring -s -u";

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

    # System packages (minimal - monitoring services are NixOS modules)
    systemPackages = pkgs: pkgs-unstable:
      with pkgs; [
        vim
        wget
        zsh
        git
        git-crypt
        btop
        fzf
        tldr
        curl # For healthchecks
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
      { name = "lxc_cloudflared"; host = "192.168.8.102"; nodePort = 9100; cadvisorPort = null; }
      { name = "lxc_plane";      host = "192.168.8.86";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_liftcraft";  host = "192.168.8.87";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_portfolio";  host = "192.168.8.88";  nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_mailer";     host = "192.168.8.89";  nodePort = 9100; cadvisorPort = 9092; }
    ];

    # === Blackbox Exporter (HTTP/HTTPS and ICMP probes) ===
    prometheusBlackboxEnable = true;

    prometheusBlackboxHttpTargets = [
      # Local services (.org.es)
      { name = "jellyfin_local"; url = "https://jellyfin.akunito.org.es"; }
      { name = "jellyseerr_local"; url = "https://jellyseerr.akunito.org.es"; }
      { name = "nextcloud_local"; url = "https://nextcloud.akunito.org.es"; }
      { name = "radarr_local"; url = "https://radarr.akunito.org.es"; }
      { name = "sonarr_local"; url = "https://sonarr.akunito.org.es"; }
      { name = "bazarr_local"; url = "https://bazarr.akunito.org.es"; }
      { name = "prowlarr_local"; url = "https://prowlarr.akunito.org.es"; }
      { name = "syncthing_local"; url = "https://syncthing.akunito.org.es"; }
      { name = "calibre_local"; url = "https://calibre.akunito.org.es"; }
      { name = "emulators_local"; url = "https://emulators.akunito.org.es"; }
      { name = "emulatorsmanager_local"; url = "https://emulatorsmanager.akunito.org.es"; }
      { name = "unifi"; url = "https://192.168.8.206:8443/"; }

      # Global services (.com)
      { name = "jellyfin_global"; url = "https://jellyfin.akunito.com"; }
      { name = "jellyseerr_global"; url = "https://jellyseerr.akunito.com"; }
      { name = "nextcloud_global"; url = "https://nextcloud.akunito.com"; }
      { name = "calibre_global"; url = "https://calibre.akunito.com"; }
      { name = "emulators_global"; url = "https://emulators.akunito.com"; }
      { name = "emulatorsmanager_global"; url = "https://emulatorsmanager.akunito.com"; }
      { name = "plane_global"; url = "https://plane.akunito.com"; }
      { name = "leftyworkout_test"; url = "https://leftyworkout-test.akunito.com"; }
      { name = "portfolio"; url = "https://info.akunito.com"; }
      { name = "status_external"; url = "https://status.akunito.com"; }
      { name = "wgui"; url = "https://wgui.akunito.com"; }
      { name = "grafana"; url = "https://monitor.akunito.org.es"; }
      { name = "prometheus"; url = "https://portal.akunito.org.es"; }

      # Local-only (no SSL)
      { name = "kuma_local"; url = "http://192.168.8.89:3001"; module = "http_2xx_nossl"; }
    ];

    prometheusBlackboxIcmpTargets = [
      { name = "truenas"; host = "192.168.20.200"; }
      { name = "guest_wifi_ap"; host = "192.168.9.2"; }
      { name = "personal_wifi_ap"; host = "192.168.8.2"; }
      { name = "switch_usw_24_g2"; host = "192.168.8.181"; }
      { name = "switch_usw_aggregation"; host = "192.168.8.180"; }
      { name = "vps"; host = "91.211.27.37"; }
      { name = "wireguard_tunnel"; host = "172.26.5.155"; }
    ];

    # === PVE Exporter (Proxmox metrics) ===
    prometheusPveExporterEnable = true;
    prometheusPveHost = "192.168.8.82";
    prometheusPveUser = "prometheus@pve";
    prometheusPveTokenName = "prometheus";
    prometheusPveTokenFile = "/etc/secrets/pve-token";

    # === SNMP Exporter (pfSense) ===
    prometheusSnmpExporterEnable = true;
    prometheusSnmpCommunity = "payphone-acetone-varied-appraiser-charting-problem-deuce-crumpet-ferocious-agreeing-grub-flyaway-silicon-curable-radio";
    prometheusSnmpTargets = [
      { name = "pfsense"; host = "192.168.8.1"; module = "pfsense"; }
    ];

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
    notificationFromEmail = "nixos@akunito.com";
    notificationToEmail = "diego88aku@gmail.com";

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
