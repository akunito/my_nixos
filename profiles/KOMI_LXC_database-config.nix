# KOMI_LXC_database Profile Configuration
# Centralized database server with PostgreSQL and Redis for Komi's infrastructure
# All services run as NixOS native modules (no Docker)
#
# Container specs:
# - IP: 192.168.1.10
# - RAM: 4096 MB
# - vCPU: 2
# - Disk: 30 GB

let
  base = import ./KOMI_LXC-base-config.nix;
  secrets = import ../secrets/komi/secrets.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "komi-database";
    envProfile = "KOMI_LXC_database"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles KOMI_LXC_database -s -u";
    serverEnv = "PROD"; # Production environment

    # Network - LXC uses Proxmox-managed networking
    ipAddress = "192.168.1.10";
    nameServers = [ "192.168.1.1" ];
    resolvedEnable = true;

    # Database credentials (from git-crypt encrypted secrets/komi/secrets.nix)
    dbMainPassword = secrets.dbMainPassword;
    redisServerPassword = secrets.redisServerPassword;

    # Firewall ports
    allowedTCPPorts = [
      22    # SSH
      5432  # PostgreSQL
      6379  # Redis
      9100  # Node Exporter
      9121  # Redis Exporter
      9187  # PostgreSQL Exporter
    ];
    allowedUDPPorts = [ ];

    # System packages (extends base with database-specific packages)
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.curl # For healthchecks
        pkgs.postgresql_17
        pkgs.redis
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Centralized Database Server (ENABLED) ===

    # PostgreSQL 17 Server
    postgresqlServerEnable = true;
    postgresqlServerPort = 5432;
    postgresqlServerDatabases = [ ]; # Komi will add databases as needed
    postgresqlServerUsers = [ ];     # Komi will add users as needed

    # Redis Server
    redisServerEnable = true;
    redisServerPort = 6379;
    redisServerMaxMemory = "1gb";
    redisServerPasswordFile = "/etc/secrets/redis-password";

    # === Database Backups (ENABLED) ===
    postgresqlBackupEnable = true;

    # Backup location (bind mount from Proxmox host)
    databaseBackupLocation = "/mnt/backups";

    # Daily backups (7 days retention)
    databaseBackupStartAt = "*-*-* 02:00:00"; # Daily at 2 AM
    databaseBackupRetainDays = 7;

    # Hourly backups (3 days retention)
    databaseBackupHourlyEnable = true;
    databaseBackupHourlySchedule = "*:00:00";
    databaseBackupHourlyRetainCount = 72;

    # Redis BGSAVE before backups
    redisBgsaveBeforeBackup = true;
    redisBgsaveTimeout = 60;

    # === Prometheus Exporters (ENABLED for monitoring) ===
    prometheusExporterEnable = true; # Node Exporter for system metrics
    prometheusExporterCadvisorEnable = false; # No Docker on this server
    prometheusPostgresExporterEnable = true;
    prometheusPostgresExporterPort = 9187;
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
    havegedEnable = false;
    fail2banEnable = false;

    # Swap file (Disabled in LXC, managed by Proxmox)
    swapFileEnable = false;

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Saturday 06:55)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 06:55:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11";

    # ============================================================================
    # EMAIL NOTIFICATIONS (Auto-update failure alerts)
    # ============================================================================
    notificationOnFailureEnable = true;
    notificationSmtpHost = "192.168.1.11"; # Komi's mailer
    notificationSmtpPort = 25;
    notificationSmtpAuth = false;
    notificationSmtpTls = false;
    notificationFromEmail = secrets.notificationFromEmail;
    notificationToEmail = secrets.alertEmail;

    # ============================================================================
    # HOMELAB DOCKER STACKS (Disabled - no Docker on database server)
    # ============================================================================
    homelabDockerEnable = false;

    systemStable = true;
  };

  userSettings = base.userSettings // {
    extraGroups = [
      "wheel"
    ];

    dockerEnable = false; # NO DOCKER on database server

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
  };
}
