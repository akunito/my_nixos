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
      3002  # Grafana
      8043  # nginx HTTPS
      9090  # Prometheus
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
      { name = "lxc_home";      host = "192.168.8.80"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_plane";     host = "192.168.8.86"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_liftcraft"; host = "192.168.8.87"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_portfolio"; host = "192.168.8.88"; nodePort = 9100; cadvisorPort = 9092; }
      { name = "lxc_mailer";    host = "192.168.8.89"; nodePort = 9100; cadvisorPort = 9092; }
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
      "docker"
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

    dockerEnable = true; # Docker for potential future monitoring containers
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
