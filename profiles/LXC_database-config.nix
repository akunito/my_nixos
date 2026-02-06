# LXC_database Profile Configuration
# Centralized database server with PostgreSQL, MariaDB, PgBouncer, and Redis
# All services run as NixOS native modules (no Docker)
#
# Database numbering:
# - PostgreSQL: plane, liftcraft (via PgBouncer on 6432 or direct on 5432)
# - MariaDB: nextcloud (port 3306)
# - Redis: db0=Plane, db1=Nextcloud, db2=LiftCraft (port 6379)
#
# Container specs:
# - IP: 192.168.8.103
# - RAM: 16 GB
# - vCPU: 6
# - Disk: 70 GB

let
  base = import ./LXC-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "database";
    profile = "proxmox-lxc";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_database -s -u";
    serverEnv = "PROD"; # Production environment

    # Network - LXC uses Proxmox-managed networking
    ipAddress = "192.168.8.103";
    nameServers = [ "192.168.8.1" ];
    resolvedEnable = true;

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      3306  # MariaDB
      5432  # PostgreSQL (direct)
      6379  # Redis
      6432  # PgBouncer
      9100  # Node Exporter
      9104  # MariaDB Exporter
      9121  # Redis Exporter
      9187  # PostgreSQL Exporter
    ];
    allowedUDPPorts = [ ];

    # System packages (minimal - database services are NixOS modules)
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
        # Database CLI tools
        postgresql_17
        mariadb
        redis
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Centralized Database Server (ENABLED) ===

    # PostgreSQL 17 Server
    postgresqlServerEnable = true;
    postgresqlServerPort = 5432;
    postgresqlServerDatabases = [ "plane" "rails_database_prod" ];
    postgresqlServerUsers = [
      {
        name = "plane";
        passwordFile = "/etc/secrets/db-plane-password";
        ensureDBOwnership = true;
      }
      {
        name = "liftcraft";
        passwordFile = "/etc/secrets/db-liftcraft-password";
        ensureDBOwnership = false; # rails_database_prod owned separately
      }
    ];

    # MariaDB Server
    mariadbServerEnable = true;
    mariadbServerPort = 3306;
    mariadbServerDatabases = [ "nextcloud" ];
    mariadbServerUsers = [
      {
        name = "nextcloud";
        database = "nextcloud";
        passwordFile = "/etc/secrets/db-nextcloud-password";
      }
    ];

    # PgBouncer Connection Pooler
    pgBouncerEnable = true;
    pgBouncerPort = 6432;
    pgBouncerPoolMode = "transaction";
    pgBouncerMaxClientConn = 1000;
    pgBouncerDefaultPoolSize = 20;

    # Redis Server
    redisServerEnable = true;
    redisServerPort = 6379;
    redisServerMaxMemory = "2gb";
    redisServerPasswordFile = "/etc/secrets/redis-password";

    # === Database Backups (ENABLED) ===
    postgresqlBackupEnable = true;
    mariadbBackupEnable = true;
    databaseBackupLocation = "/var/backup/databases";
    databaseBackupStartAt = "*-*-* 02:00:00"; # Daily at 2 AM
    databaseBackupRetainDays = 7;

    # === Prometheus Exporters (ENABLED for monitoring) ===
    prometheusExporterEnable = true; # Node Exporter for system metrics
    prometheusExporterCadvisorEnable = false; # No Docker on this server
    prometheusPostgresExporterEnable = true;
    prometheusPostgresExporterPort = 9187;
    prometheusMariadbExporterEnable = true;
    prometheusMariadbExporterPort = 9104;
    prometheusRedisExporterEnable = true;
    prometheusRedisExporterPort = 9121;

    # === Package Modules ===
    systemBasicToolsEnable = false; # Minimal server - packages defined above
    systemNetworkToolsEnable = false;

    # === Shell Features ===
    atuinAutoSync = false;

    # === System Services & Features (ALL DISABLED - Database Server) ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    starCitizenModules = false;

    # Optimizations
    havegedEnable = false; # Redundant on modern kernels
    fail2banEnable = false; # Behind firewall, no public access

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Saturday 06:55)
    # Database server updates BEFORE dependent services (LXC_HOME, LXC_plane, etc.)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 06:55:00"; # 5 minutes before dependent services
    autoUpgradeRestartDocker = false; # No Docker on database server
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
    # HOMELAB DOCKER STACKS (Disabled - no Docker on database server)
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

    dockerEnable = false; # NO DOCKER on database server
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

    # === Shell Customization (RED for database server - critical infrastructure) ===
    starshipHostStyle = "bold red";

    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Ensure proper terminal type for colors and cursor visibility
      export TERM=''${TERM:-xterm-256color}
      export COLORTERM=truecolor

      PROMPT=" ◉ %U%F{red}%n%f%u@%U%F{red}%m%f%u:%F{yellow}%~%f
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
