# Default systemSettings and userSettings
# These are the common values shared across all profiles
# Profile-specific configs will override these values

{ pkgs, ... }:

{
  systemSettings = {
    # System architecture - most profiles use x86_64-linux
    system = "x86_64-linux";

    # Operating system type - "linux" (NixOS) or "darwin" (macOS)
    osType = "linux";

    # Common defaults (profile-specific values will override)
    timezone = "Europe/Warsaw";
    locale = "en_US.UTF-8";
    timeLocale = "en_GB.UTF-8"; # Locale for time/date formatting (uses Monday as first day of week)
    bootMode = "uefi";
    bootMountPath = "/boot";
    grubDevice = "";
    grubEnableCryptodisk = false; # Enable GRUB cryptodisk support for encrypted /boot (LUKS)

    # GPU defaults
    gpuType = "intel"; # Options: "amd", "intel", "nvidia", "none" (for VMs/containers)

    # Kernel defaults
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = [
      # i2c modules removed - not needed in VMs/containers
      # Physical machines can add back if needed for lm-sensors, OpenRGB, or ddcutil
    ];

    # Security defaults
    fuseAllowOther = false;
    doasEnable = false;
    sudoEnable = true;
    DOASnoPass = false;
    wrappSudoToDoas = false;
    sudoNOPASSWD = true;
    wheelNeedsPassword = true; # Set to false for fully passwordless sudo (including sudo -v)
    # Sudo timestamp timeout (minutes). When set, applies as:
    #   Defaults:<user> timestamp_timeout=<minutes>
    # Keep null to use system default.
    sudoTimestampTimeoutMinutes = null;
    # SSH agent authentication for sudo (allows passwordless sudo over SSH with agent forwarding)
    # When enabled, sudo authenticates via forwarded SSH agent (-A flag)
    # Local sessions without agent still require password
    sshAgentSudoEnable = false;
    sshAgentSudoAuthorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
    sudoCommands = [
      {
        command = "/run/current-system/sw/bin/systemctl suspend";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/restic";
        options = [
          "NOPASSWD"
          "SETENV"
        ];
      }
    ];
    pkiCertificates = [ ];

    # Polkit defaults
    polkitEnable = false;
    polkitRules = ''
      polkit.addRule(function(action, subject) {
        if (
          subject.isInGroup("users") && (
            // Allow running rsync and restic
            (action.id == "org.freedesktop.policykit.exec" &&
              (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
              action.lookup("command") == "/run/current-system/sw/bin/restic"))
          )
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    # Backup defaults
    resticWrapper = true;
    rsyncWrapper = true;
    homeBackupEnable = false;
    homeBackupDescription = "Backup Home Directory with Restic";
    homeBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/personal_backup.sh";
    homeBackupUser = "akunito";
    homeBackupTimerDescription = "Timer for home_backup service";
    homeBackupOnCalendar = "0/6:00:00";
    homeBackupCallNextEnabled = false;
    homeBackupCallNext = [ "remote_backup.service" ];

    remoteBackupEnable = false;
    remoteBackupDescription = "Copy Restic Backup to Remote Server";
    remoteBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/personal_backup_remote.sh";
    remoteBackupUser = "akunito";
    remoteBackupTimerDescription = "Timer for remote_backup service";

    # Network defaults
    networkManager = true;
    useNetworkd = false; # Use systemd-networkd instead of NetworkManager (for headless servers)
    defaultGateway = null;
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    wifiPowerSave = true;
    resolvedEnable = false;

    # Network bonding (LACP link aggregation)
    networkBondingEnable = false; # Enable network bonding (requires switch LAG configuration)
    networkBondingMode = "802.3ad"; # Bonding mode: "802.3ad" (LACP), "balance-rr", "active-backup", etc.
    networkBondingInterfaces = []; # List of interfaces to bond (e.g., ["enp11s0f0" "enp11s0f1"])
    networkBondingDhcp = true; # Use DHCP for bond interface
    networkBondingStaticIp = null; # Static IP config: { address = "192.168.8.96/24"; gateway = "192.168.8.1"; }
    networkBondingLacpRate = "fast"; # LACP rate: "fast" (1s) or "slow" (30s)
    networkBondingMiimon = "100"; # Link check interval in milliseconds
    networkBondingXmitHashPolicy = "layer3+4"; # Hash policy: "layer2", "layer3+4", "encap3+4"

    # Service defaults
    havegedEnable = true; # Can disable on modern kernels (5.4+) where it's redundant
    fail2banEnable = true; # Can disable for systems behind firewall

    # Journald defaults (applied to all profiles)
    journaldMaxUse = "100M";
    journaldMaxRetentionSec = "14day";
    journaldCompress = true;

    # Firewall defaults
    firewall = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # Drive defaults
    mount2ndDrives = false;
    bootSSH = false;
    # Disk defaults - all disabled by default, profiles enable as needed
    disk1_enabled = false;
    disk1_name = "/mnt/2nd_NVME";
    disk1_device = "/dev/mapper/2nd_NVME";
    disk1_fsType = "ext4";
    disk1_options = [
      "nofail"
      "x-systemd.device-timeout=3s"
    ];
    disk2_enabled = false;
    disk2_name = "/mnt/DATA_SATA3";
    disk2_device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
    disk2_fsType = "ntfs3";
    disk2_options = [
      "nofail"
      "x-systemd.device-timeout=3s"
    ];
    disk3_enabled = false;
    disk3_name = "/mnt/NFS_media";
    disk3_device = "192.168.20.200:/mnt/hddpool/media";
    disk3_fsType = "nfs4";
    disk3_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk4_enabled = false;
    disk4_name = "/mnt/NFS_emulators";
    disk4_device = "192.168.20.200:/mnt/ssdpool/emulators";
    disk4_fsType = "nfs4";
    disk4_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk5_enabled = false;
    disk5_name = "/mnt/NFS_library";
    disk5_device = "192.168.20.200:/mnt/ssdpool/library";
    disk5_fsType = "nfs4";
    disk5_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk6_enabled = false;
    disk6_name = "/mnt/DATA";
    disk6_device = "/dev/disk/by-uuid/48B8BD48B8BD34F2";
    disk6_fsType = "ntfs3";
    disk6_options = [
      "nofail"
      "x-systemd.device-timeout=3s"
    ];
    disk7_enabled = false;
    disk7_name = "/mnt/EXT";
    disk7_device = "/dev/disk/by-uuid/b6be2dd5-d6c0-4839-8656-cb9003347c93";
    disk7_fsType = "ext4";
    disk7_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];

    # NFS defaults
    nfsServerEnable = false;
    nfsExports = ''
      /mnt/example   192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
      /mnt/example2  192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
    '';
    nfsClientEnable = false;
    nfsMounts = [ ];
    nfsAutoMounts = [ ];

    # SSH defaults
    authorizedKeys = [ ];
    hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];

    # Printer defaults
    servicePrinting = false;
    networkPrinters = false;
    sharePrinter = false;

    # Power management defaults
    iwlwifiDisablePowerSave = false;
    TLP_ENABLE = false;
    PROFILE_ON_BAT = "performance";
    PROFILE_ON_AC = "performance";
    WIFI_PWR_ON_AC = "off";
    WIFI_PWR_ON_BAT = "off";
    # Battery charge thresholds (default: full charge)
    START_CHARGE_THRESH_BAT0 = 95;
    STOP_CHARGE_THRESH_BAT0 = 100;
    # CPU Energy Performance Policy (default: balance performance/power)
    CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
    CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
    # CPU Scaling Governor (default: powersave is usually best for modern Intel CPUs)
    CPU_SCALING_GOVERNOR_ON_AC = "performance";
    CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

    INTEL_GPU_MIN_FREQ_ON_AC = 300;
    INTEL_GPU_MIN_FREQ_ON_BAT = 300;
    LOGIND_ENABLE = false;
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    powerKey = "ignore";
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;

    # Performance profile flags (for io-scheduler.nix and performance.nix)
    # Enable ONE of these based on hardware type - they are mutually exclusive
    enableDesktopPerformance = false; # Aggressive settings for maximum performance on desktop systems
    enableLaptopPerformance = false;  # Conservative settings for battery life while maintaining responsiveness

    # Feature flags defaults
    starCitizenModules = false;
    starcitizenEnable = false;
    protongamesEnable = false;
    gamemodeEnable = false; # Enable GameMode for performance optimization during gaming
    vivaldiPatch = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    stylixEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    aichatEnable = false; # Enable aichat CLI tool with OpenRouter support
    nixvimEnabled = false; # Enable NixVim configuration (Cursor IDE-like experience)
    lmstudioEnabled = false; # Enable LM Studio configuration and MCP server support
    swaybgPlusEnable = false; # [DEPRECATED] Enable SwayBG+ (GUI/CLI wallpaper manager) - use waypaperEnable instead
    waypaperEnable = false; # Enable Waypaper GUI wallpaper manager (requires swwwEnable)
    swwwEnable = false; # Enable swww wallpaper manager for SwayFX (robust across reboot + HM rebuilds); disables other wallpaper owners in Sway
    nextcloudEnable = false; # Enable Nextcloud Desktop Client autostart in Sway session
    swayPrimaryMonitor = null; # Optional: Primary monitor for SwayFX dock (e.g., "DP-1")

    # Thinkpad hardware optimizations (via nixos-hardware)
    thinkpadEnable = false; # Enable Lenovo Thinkpad hardware optimizations
    thinkpadModel = ""; # Thinkpad model (e.g., "lenovo-thinkpad-l14-intel", "lenovo-thinkpad-x280", "lenovo-thinkpad-t490")

    # GPU-related feature flags
    amdLACTdriverEnable = false; # Enable LACT (Linux AMD GPU Control Application) for AMD GPU management

    # SDDM feature flags (display manager customization)
    sddmForcePasswordFocus = false; # Force password field focus (fixes multi-monitor focus issues)
    sddmBreezePatchedTheme = false; # Use patched Breeze theme with custom settings
    sddmSetupScript = null; # Custom SDDM setup script (e.g., for monitor rotation). Set to string with script content.

    # Shell feature flags
    atuinAutoSync = false; # Enable Atuin shell history cloud sync

    # Hyprland feature flags
    hyprprofilesEnable = false; # Enable hyprprofiles for Hyprland

    # Development tools feature flags
    developmentToolsEnable = false; # Enable development IDEs and cloud tools (Cursor, Claude Code, Azure CLI, etc.)

    # Package module feature flags
    systemBasicToolsEnable = true; # Enable basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = false; # Enable advanced networking tools (nmap, traceroute, dnsutils, etc.)

    # Homelab feature flags
    cloudflaredEnable = false; # Enable Cloudflare tunnel service (remotely-managed, token at /etc/secrets/cloudflared-token)
    acmeEnable = false; # Enable ACME (Let's Encrypt) certificate management
    acmeEmail = "admin@example.com"; # Email for Let's Encrypt notifications
    grafanaEnable = false; # Enable Grafana/Prometheus monitoring stack (only on monitoring server)
    gpuMonitoringEnable = true; # Enable GPU monitoring (btop-rocm, nvtop, radeontop)

    # === Control Panel (Web-based infrastructure management) ===
    controlPanelEnable = false; # Enable NixOS Control Panel web service
    controlPanelNativeEnable = false; # Enable NixOS Control Panel native desktop app
    controlPanelPort = 3100; # Port for control panel web UI
    dotfilesPath = "/home/akunito/.dotfiles"; # Path to dotfiles repository

    # === Prometheus Exporters (for monitored nodes) ===
    prometheusExporterEnable = false; # Enable Node Exporter on this host
    prometheusExporterCadvisorEnable = false; # Enable cAdvisor for Docker metrics on this host
    prometheusNodeExporterPort = 9100; # Port for Node Exporter
    prometheusCadvisorPort = 9092; # Port for cAdvisor
    # Remote targets for Prometheus scraping (used by monitoring server only)
    prometheusRemoteTargets = [
      # Example:
      # { name = "lxc_home"; host = "192.168.8.80"; nodePort = 9100; cadvisorPort = 9092; }
    ];

    # === Blackbox Exporter (for HTTP/HTTPS and ICMP probes) ===
    prometheusBlackboxEnable = false;
    prometheusBlackboxHttpTargets = [];   # [{name, url, module}]
    prometheusBlackboxIcmpTargets = [];   # [{name, host}]

    # === PVE Exporter (Proxmox metrics) ===
    prometheusPveExporterEnable = false;
    prometheusPveHost = "";
    prometheusPveUser = "prometheus@pve";
    prometheusPveTokenName = "prometheus";
    prometheusPveTokenFile = "";  # Path to file containing API token

    # === PVE Backup Monitoring (queries Proxmox API for backup status) ===
    prometheusPveBackupEnable = false;

    # === pfSense Backup Monitoring (checks backup files on Proxmox NFS) ===
    prometheusPfsenseBackupEnable = false;
    prometheusPfsenseBackupProxmoxHost = "192.168.8.82";
    prometheusPfsenseBackupPath = "/mnt/pve/proxmox_backups/pfsense";

    # === SNMP Exporter (pfSense/network devices) ===
    prometheusSnmpExporterEnable = false;
    prometheusSnmpCommunity = "";  # SNMP community string
    prometheusSnmpTargets = [];    # [{name, host, module}]

    # === Graphite Exporter (TrueNAS pushes metrics here) ===
    prometheusGraphiteEnable = false;
    prometheusGraphitePort = 9109;       # Prometheus scrape port
    prometheusGraphiteInputPort = 2003;  # Graphite input port

    # === Centralized Database Server (LXC_database) ===
    # PostgreSQL server configuration
    postgresqlServerEnable = false;
    postgresqlServerPort = 5432;
    postgresqlServerPackage = null; # Set to specific package version (e.g., pkgs.postgresql_17)
    postgresqlServerDatabases = []; # List of database names to create
    postgresqlServerUsers = []; # List of { name, passwordFile, ensureDBOwnership } records
    postgresqlServerAuthentication = ""; # Extra pg_hba.conf entries

    # MariaDB server configuration
    mariadbServerEnable = false;
    mariadbServerPort = 3306;
    mariadbServerDatabases = []; # List of database names to create
    mariadbServerUsers = []; # List of { name, passwordFile, privileges } records

    # PgBouncer connection pooler
    pgBouncerEnable = false;
    pgBouncerPort = 6432;
    pgBouncerPoolMode = "transaction";
    pgBouncerMaxClientConn = 1000;
    pgBouncerDefaultPoolSize = 20;

    # Redis server configuration
    redisServerEnable = false;
    redisServerPort = 6379;
    redisServerMaxMemory = "1gb";
    redisServerPasswordFile = ""; # Path to file containing Redis password

    # Database backup configuration
    postgresqlBackupEnable = false;
    mariadbBackupEnable = false;
    databaseBackupLocation = "/var/backup/databases";
    databaseBackupStartAt = "*-*-* 02:00:00"; # Daily at 2 AM
    databaseBackupRetainDays = 7;

    # Hourly backup configuration (in addition to daily)
    databaseBackupHourlyEnable = false; # Enable hourly backups (custom format only, 3-day retention)
    databaseBackupHourlySchedule = "*:00:00"; # Every hour at :00
    databaseBackupHourlyRetainCount = 72; # Keep 72 most recent (3 days of hourly backups)

    # Redis BGSAVE before backups (ensures Redis data consistency)
    redisBgsaveBeforeBackup = false; # Trigger Redis BGSAVE before database backups
    redisBgsaveTimeout = 60; # Seconds to wait for BGSAVE completion

    # Database monitoring exporters
    prometheusPostgresExporterEnable = false;
    prometheusPostgresExporterPort = 9187;
    prometheusMariadbExporterEnable = false;
    prometheusMariadbExporterPort = 9104;
    prometheusRedisExporterEnable = false;
    prometheusRedisExporterPort = 9121;

    # === Database Client Credentials (for workstations) ===
    # Generate ~/.pgpass and ~/.my.cnf for CLI tools and DBeaver
    dbCredentialsEnable = false;
    # Database server host (LXC_database)
    dbCredentialsHost = "192.168.8.103";
    # PostgreSQL credentials (plane, liftcraft databases)
    dbCredentialsPostgres = []; # List of { database, user, password }
    # MariaDB credentials (nextcloud database)
    dbCredentialsMariadb = []; # List of { database, user, password }
    # Redis credentials
    dbCredentialsRedisPassword = "";

    # Sway/SwayFX monitor inventory (data-only; safe default for all profiles)
    # Profiles can override/populate this and then build `swayKanshiSettings` from it.
    swayMonitorInventory = { };

    # Sway/SwayFX dynamic outputs (kanshi)
    #
    # Default: enabled with a generic "enable everything" profile so new/unknown monitors work
    # without needing an explicit per-profile layout.
    #
    # Profiles (e.g. DESK) can override this with explicit, anti-drift, hardware-ID-based layouts.
    # This is consumed by `user/wm/sway/kanshi.nix` (only when Sway module is enabled).
    swayKanshiSettings = [
      {
        profile = {
          name = "default-auto";
          # IMPORTANT: This is intentionally non-opinionated: enable all outputs and let Sway place them.
          # Profiles can override with explicit positions/scales when needed.
          outputs = [
            {
              criteria = "*";
              status = "enable";
            }
          ];
          # Keep workspaces grouped per-output deterministically.
          # Use user profile PATH (swaysome is installed by the Sway module).
          exec = [
            # IMPORTANT: start swaysome groups at 1 so group 0 (workspaces 1-10) is never used.
            "$HOME/.nix-profile/bin/swaysome init 1"
            "$HOME/.nix-profile/bin/swaysome rearrange-workspaces"
            "$HOME/.config/sway/scripts/swaysome-assign-groups.sh"
          ];
        };
      }
    ];

    # Sway/SwayFX keyboard layouts (multi-language support)
    # Format: list of XKB layout codes with optional variants in parentheses
    # Example: [ "us(altgr-intl)" "es" "pl" ] → layouts: "us,es,pl", variants: "altgr-intl,,"
    swayKeyboardLayouts = [
      "us(altgr-intl)"
      "es"
      "pl"
    ];

    # Sway/SwayFX idle configuration
    swayIdleDisableMonitorPowerOff = false; # Disable monitor power-off timeout (useful for monitors with DPMS wake issues)

    # Monitor management (imperative GUI approach)
    nwgDisplaysEnable = false;           # Install nwg-displays for visual monitor config
    workspaceGroupsGuiEnable = false;    # Install workspace groups GUI
    kanshiImperativeMode = false;        # User-managed kanshi config (not Nix)

    # Font defaults - will be computed based on systemStable in flake-base.nix
    # This is just a placeholder
    fonts = [ ];

    # Server environment (DEV, TEST, PROD) - used by applications/docker to detect environment
    serverEnv = "DEV"; # Default to DEV, profiles override as needed

    # Environment profile variable - used by Claude Code for context awareness
    # This identifies which profile/machine is running, enabling remote operations
    envProfile = "unknown"; # Default, overridden per profile (e.g., "DESK", "LXC_HOME")

    # System defaults
    swapFileEnable = false;
    swapFileSyzeGB = 32;
    downloadBufferSize = "134217728";
    systemStateVersion = "24.11";
    systemStable = false;

    # Update defaults
    autoSystemUpdateEnable = false; # Disabled by default - stable profiles explicitly enable
    autoSystemUpdateDescription = "Auto Update System service";
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoSystemUpdate.sh";
    autoSystemUpdateUser = "root";
    autoSystemUpdateTimerDescription = "Auto Update System timer";
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:00:00"; # Weekly Saturday default
    autoSystemUpdateCallNext = [ "autoUserUpdate.service" ];

    autoUserUpdateEnable = false; # Disabled by default - stable profiles explicitly enable
    autoUserUpdateDescription = "Auto User Update";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "akunito";

    # Restart docker containers after successful rebuild
    autoUpgradeRestartDocker = false;

    # Home-manager branch for auto-update (stable = release-25.11, unstable = master)
    autoUserUpdateBranch = "master"; # Default unstable, stable profiles override to "release-25.11"

    # Homelab docker stacks - start docker-compose stacks on boot
    homelabDockerEnable = false; # Enable systemd service for homelab docker stacks

    # pfSense backup configuration
    pfsenseBackupEnable = false; # Enable daily pfSense config backup
    pfsenseBackupOnCalendar = "daily"; # Backup schedule (systemd calendar format)
    pfsenseBackupDir = "/mnt/DATA_4TB/backups/pfsense"; # Backup directory

    # Email notifications for auto-update failures
    notificationOnFailureEnable = false; # Enable email notifications on auto-update failure
    notificationSmtpHost = ""; # SMTP relay host (e.g., "192.168.8.1")
    notificationSmtpPort = 25; # SMTP port (25 for relay, 587 for submission)
    notificationSmtpAuth = false; # Enable SMTP authentication
    notificationSmtpTls = false; # Enable TLS/STARTTLS
    notificationSmtpUser = ""; # SMTP username (if auth enabled)
    notificationSmtpPasswordFile = ""; # Path to file containing SMTP password
    notificationFromEmail = "noreply@localhost"; # From email address
    notificationToEmail = ""; # Recipient email address

    # Profile install invocation (used by Waybar update button)
    # Each profile should override this with the exact install.sh invocation for that profile.
    # Example: "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK -s"
    installCommand = "";

    # System packages - empty by default, profiles specify their own
    systemPackages = [ ];

    # Background package - handled in flake-base.nix with proper self reference
    # Profiles can override this if needed

    # ============================================================================
    # TAILSCALE/HEADSCALE MESH VPN
    # ============================================================================
    tailscaleEnable = false; # Enable Tailscale client
    tailscaleAdvertiseRoutes = []; # Subnets to advertise as exit routes (e.g., ["192.168.8.0/24"])
    tailscaleLoginServer = ""; # Custom login server URL (for Headscale, e.g., "https://headscale.example.com")
    tailscaleExitNode = false; # Act as exit node for internet traffic
    tailscaleAcceptRoutes = false; # Accept advertised routes from other nodes
    tailscaleAcceptDns = true; # Accept DNS from Tailscale (set false if always on LAN)
    tailscaleLanAutoToggle = false; # Auto-toggle accept-routes/dns based on LAN presence (for roaming laptops)
    tailscaleLanGateway = "192.168.8.1"; # Gateway IP to detect home LAN (ping target for auto-toggle)
    tailscaleGuiAutostart = false; # Auto-start Tailscale GUI (trayscale) with desktop session

    # ============================================================================
    # DARWIN (macOS) SETTINGS
    # ============================================================================
    # These settings only apply when osType = "darwin"

    darwin = {
      # === Homebrew Configuration ===
      homebrewEnable = true; # Enable Homebrew for GUI apps (casks)
      homebrewCasks = [ ]; # GUI apps to install via Homebrew (e.g., "firefox", "discord")
      homebrewFormulas = [ ]; # CLI tools to install via Homebrew (prefer Nix when possible)
      homebrewOnActivation = {
        autoUpdate = false; # Don't auto-update Homebrew on nix-darwin activation
        cleanup = "zap"; # Remove unlisted casks/formulas (keep system clean)
        upgrade = true; # Upgrade outdated packages on activation
      };

      # === Dock Preferences ===
      dockAutohide = true; # Automatically hide the Dock
      dockAutohideDelay = 0.0; # Delay before Dock appears (0 = instant)
      dockOrientation = "bottom"; # Dock position: "bottom", "left", "right"
      dockShowRecents = false; # Don't show recent apps in Dock
      dockMinimizeToApplication = true; # Minimize windows into app icon
      dockTileSize = 48; # Icon size in pixels

      # === Finder Preferences ===
      finderShowExtensions = true; # Show file extensions
      finderShowHiddenFiles = true; # Show hidden files (dotfiles)
      finderShowPathBar = true; # Show path bar at bottom
      finderShowStatusBar = true; # Show status bar at bottom
      finderDefaultViewStyle = "Nlsv"; # Default view: "icnv" (icon), "Nlsv" (list), "clmv" (column), "glyv" (gallery)
      finderAppleShowAllFiles = true; # Show all files including system files

      # === Keyboard Preferences ===
      keyboardInitialKeyRepeat = 15; # Delay before key repeat (lower = faster)
      keyboardKeyRepeat = 2; # Key repeat rate (lower = faster)
      keyboardFnState = true; # Use F1, F2, etc. as standard function keys

      # === Trackpad Preferences ===
      trackpadTapToClick = true; # Enable tap to click
      trackpadSecondaryClick = true; # Enable right-click via two-finger tap

      # === Security & Privacy ===
      touchIdSudo = true; # Enable Touch ID for sudo authentication

      # === General UI Preferences ===
      darkMode = true; # Enable dark mode
      scrollDirection = true; # Natural scrolling (true = natural, false = traditional)
    };
  };

  userSettings = {
    # User defaults
    email = "diego88aku@gmail.com";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    # Theme and WM defaults
    theme = "miramare";
    wm = "plasma6";
    wmType = "wayland"; # Will be computed from wm
    wmEnableHyprland = false;

    # Feature flags
    dockerEnable = true;
    virtualizationEnable = true;
    qemuGuestAddition = false;

    protongamesEnable = false;
    starcitizenEnable = false;
    GOGlauncherEnable = false;
    dolphinEmulatorPrimehackEnable = false;
    steamPackEnable = false;
    rpcs3Enable = false;

    # Package module feature flags
    userBasicPkgsEnable = true; # Enable basic user packages (browsers, office, communication, etc.)
    userAiPkgsEnable = false; # Enable AI & ML packages (lmstudio, ollama-rocm)
    gamesEnable = false; # Enable gaming packages and tools (Lutris, Bottles, RetroArch, etc.)

    # === Shell Customization ===
    starshipEnable = true; # Enable Starship cross-shell prompt with Nerd Font symbols
    starshipHostStyle = "bold white"; # Color for username@hostname in starship prompt (per-profile customization)

    # Git defaults
    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    # Application defaults
    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";
    fontPkg = pkgs.intel-one-mono;
    editor = "nano";
    fileManager = "ranger"; # "ranger" or "dolphin"

    # Home packages - empty by default, profiles specify their own
    homePackages = [ ];

    # ZSH prompt defaults
    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      # Multi-line editing with Shift+Enter
      # Create a custom widget to insert a literal newline
      insert-newline() {
        LBUFFER="$LBUFFER"$'\n'
      }
      zle -N insert-newline

      # Bind Shift+Enter to insert newline (various terminal escape sequences)
      bindkey '^[[13;2u' insert-newline    # Kitty, Alacritty, WezTerm (CSI u mode)
      bindkey '^[[27;2;13~' insert-newline # Some other terminals
      bindkey '^[OM' insert-newline        # Alternative sequence

      # For tmux: enable focus events and extended keys
      if [[ -n "$TMUX" ]]; then
        bindkey '^[[13;2u' insert-newline
      fi

      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{magenta}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    # SSH config defaults
    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519 # Generate this key for github if needed
        AddKeysToAgent yes
    '';

    # Version
    homeStateVersion = "24.11";

    # Editor spawn command - computed from editor and term
    spawnEditor = "exec kitty -e nano"; # Will be computed

    # ============================================================================
    # DARWIN (macOS) USER SETTINGS
    # ============================================================================
    # These settings only apply when systemSettings.osType = "darwin"

    # === Hammerspoon (macOS window manager & automation) ===
    hammerspoonEnable = false; # Enable Hammerspoon configuration management
    hammerspoonConfig = "default"; # Config variant: "default", "komi", or custom
    # Hyperkey bindings (Cmd+Ctrl+Alt+Shift) for app launching
    # Format: { key = "s"; app = "Spotify"; } or { key = "1"; action = "cycleApp"; apps = ["Arc" "Cursor"]; }
    hammerspoonAppBindings = [ ];
    # Window management bindings
    hammerspoonWindowBindings = {
      maximize = "m";
      minimize = "h";
      moveLeft = "Left";
      moveRight = "Right";
      reload = "r";
    };
  };
}
