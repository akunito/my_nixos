# KOMI_LXC_monitoring Profile Configuration
# Centralized monitoring server with Grafana + Prometheus for Komi's infrastructure
# Scrapes metrics from all KOMI_LXC containers
#
# Container specs:
# - IP: 192.168.8.12
# - RAM: 2048 MB
# - vCPU: 2
# - Disk: 20 GB

let
  base = import ./KOMI_LXC-base-config.nix;
  secrets = import ../secrets/komi/secrets.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "komi-monitoring";
    profile = "proxmox-lxc";
    envProfile = "KOMI_LXC_monitoring"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles KOMI_LXC_monitoring -s -u";
    serverEnv = "PROD"; # Production environment

    # Domain settings (passed to grafana.nix, acme.nix)
    wildcardLocal = secrets.wildcardLocal;
    publicDomain = secrets.publicDomain;
    grafanaAlertsFrom = secrets.notificationFromEmail; # Komi uses notification email for alerts

    # Network - LXC uses Proxmox-managed networking
    ipAddress = "192.168.8.12";
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
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Monitoring Stack (enabled - this IS the monitoring server) ===
    grafanaEnable = true;

    # === Prometheus Exporters (DISABLED - this is the server, not a target) ===
    prometheusExporterEnable = false;
    prometheusExporterCadvisorEnable = false;

    # === Remote Targets for Prometheus Scraping (Komi's containers) ===
    prometheusRemoteTargets = [
      { name = "komi_database";   host = "192.168.8.10"; nodePort = 9100; cadvisorPort = null; }
      { name = "komi_mailer";     host = "192.168.8.11"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "komi_proxy";      host = "192.168.8.13"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "komi_tailscale";  host = "192.168.8.14"; nodePort = 9100; cadvisorPort = null; }
    ];

    # === Application Metrics (Database exporters) ===
    prometheusAppTargets = [
      { name = "postgresql"; host = "192.168.8.10"; port = 9187; }
      { name = "redis";      host = "192.168.8.10"; port = 9121; }
    ];

    # === Blackbox Exporter (HTTP/HTTPS and ICMP probes) ===
    prometheusBlackboxEnable = true;

    # Komi will add HTTP targets as she deploys services
    prometheusBlackboxHttpTargets = [
      { name = "kuma"; url = "http://192.168.8.11:3001"; module = "http_2xx_nossl"; }
    ];

    prometheusBlackboxIcmpTargets = [
      { name = "router";   host = "192.168.8.1"; }
      { name = "proxmox";  host = "192.168.8.3"; }
    ];

    prometheusBlackboxTlsTargets = [];

    # === PVE Exporter (DISABLED until PVE API token is created) ===
    prometheusPveExporterEnable = false;
    prometheusPveHost = "192.168.8.3";
    prometheusPveUser = "prometheus@pve";
    prometheusPveTokenName = "prometheus";
    prometheusPveTokenFile = "/etc/secrets/pve-token";

    # === PVE Backup Monitoring (DISABLED until PVE API token is created) ===
    prometheusPveBackupEnable = false;

    # === SNMP Exporter (DISABLED initially - Komi can enable if she has SNMP devices) ===
    prometheusSnmpExporterEnable = false;
    prometheusSnmpTargets = [];

    # === Graphite Exporter (DISABLED - enable if Komi has TrueNAS) ===
    prometheusGraphiteEnable = false;

    # === Package Modules ===
    systemBasicToolsEnable = false;
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
    havegedEnable = false;
    fail2banEnable = false;

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:00)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:00:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11";

    # ============================================================================
    # EMAIL NOTIFICATIONS (Auto-update failure alerts)
    # ============================================================================
    notificationOnFailureEnable = true;
    notificationSmtpHost = "192.168.8.11"; # Komi's mailer
    notificationSmtpPort = 25;
    notificationSmtpAuth = false;
    notificationSmtpTls = false;
    notificationFromEmail = secrets.notificationFromEmail;
    notificationToEmail = secrets.alertEmail;

    # ============================================================================
    # HOMELAB DOCKER STACKS (Disabled - no Docker stacks on monitoring server)
    # ============================================================================
    homelabDockerEnable = false;

    systemStable = true;
  };

  userSettings = base.userSettings // {
    extraGroups = [
      "wheel"
    ];

    dockerEnable = false; # No Docker needed on monitoring server

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
  };
}
