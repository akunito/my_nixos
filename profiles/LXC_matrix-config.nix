# LXC_matrix Profile Configuration
# Matrix Synapse server + Element Web + Claude Bot
#
# Services:
#   - Matrix Synapse: Self-hosted Matrix homeserver
#   - Element Web: Matrix web client
#   - Claude Bot: CLI-based bot for Claude Code assistance via Matrix
#
# Container specs:
#   - Proxmox ID: 251
#   - IP: 192.168.8.104
#   - RAM: 4 GB
#   - vCPU: 2
#   - Disk: 20 GB
#
# Database: PostgreSQL on LXC_database (192.168.8.103), db: matrix
# Redis: db4 on LXC_database for sessions/presence

let
  base = import ./LXC-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "matrix";
    profile = "proxmox-lxc";
    envProfile = "LXC_matrix"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_matrix -s -u";
    serverEnv = "PROD"; # Production environment

    # Network - LXC uses Proxmox-managed networking
    ipAddress = "192.168.8.104";
    nameServers = [ "192.168.8.1" ];
    resolvedEnable = true;

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      80    # HTTP
      443   # HTTPS
      8008  # Synapse internal
      8080  # Element Web
      9000  # Synapse metrics (Prometheus)
      9100  # Prometheus Node Exporter
      9092  # cAdvisor (Docker metrics)
    ];
    allowedUDPPorts = [ ];

    # System packages (extends base with Matrix-specific packages)
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.curl # For healthchecks
        # Python for Claude bot
        pkgs.python311
        pkgs.python311Packages.aiohttp
        pkgs.python311Packages.aiosqlite
        # Note: matrix-nio installed via pip in bot virtualenv
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Prometheus Exporters (enabled for monitoring) ===
    prometheusExporterEnable = true; # Node Exporter for system metrics
    prometheusExporterCadvisorEnable = true; # cAdvisor for Docker container metrics

    # === Package Modules ===
    systemBasicToolsEnable = false; # Minimal server - packages defined above
    systemNetworkToolsEnable = false;

    # === Shell Features ===
    atuinAutoSync = false;

    # === System Services & Features (ALL DISABLED - Matrix Server) ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    starCitizenModules = false;

    # Optimizations
    havegedEnable = false; # Redundant on modern kernels
    fail2banEnable = false; # Behind firewall

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:40)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:40:00"; # After other LXC containers
    autoUpgradeRestartDocker = true; # Restart Matrix containers after rebuild
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
    # HOMELAB DOCKER STACKS (Start on boot - Matrix Synapse + Element)
    # ============================================================================
    homelabDockerEnable = true;

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

    dockerEnable = true; # Docker for Synapse + Element
    virtualizationEnable = false;
    qemuGuestAddition = false;

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      pkgs.zsh
      pkgs.git
      pkgs.git-crypt
      pkgs-unstable.claude-code # For testing/fallback
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) - ALL DISABLED (Headless Server) ===
    userBasicPkgsEnable = false;
    userAiPkgsEnable = false;

    # === Shell Customization (Purple for Matrix - chat/communication server) ===
    starshipHostStyle = "bold #9B59B6";

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Ensure proper terminal type for colors and cursor visibility
      export TERM=''${TERM:-xterm-256color}
      export COLORTERM=truecolor

      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{magenta}%m%f%u:%F{yellow}%~%f
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

      # SSH config for cross-node access (Claude bot uses these)
      Host desk
        HostName 192.168.8.50
        User akunito
        ForwardAgent yes

      Host laptop
        HostName 192.168.8.51
        User akunito
        ForwardAgent yes

      Host lxc-home
        HostName 192.168.8.80
        User akunito

      Host lxc-database
        HostName 192.168.8.103
        User akunito

      Host proxmox
        HostName 192.168.8.82
        User root
    '';
  };
}
