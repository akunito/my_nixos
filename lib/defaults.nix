# Default systemSettings and userSettings
# These are the common values shared across all profiles
# Profile-specific configs will override these values

{ pkgs, ... }:

{
  systemSettings = {
    # System architecture - most profiles use x86_64-linux
    system = "x86_64-linux";

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
    # Sudo timestamp timeout (minutes). When set, applies as:
    #   Defaults:<user> timestamp_timeout=<minutes>
    # Keep null to use system default.
    sudoTimestampTimeoutMinutes = null;
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
    swaybgPlusEnable = false; # Enable SwayBG+ (GUI/CLI wallpaper manager) and disable Stylix swaybg service when active
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
    grafanaEnable = true; # Enable Grafana/Prometheus monitoring stack
    gpuMonitoringEnable = true; # Enable GPU monitoring (btop-rocm, nvtop, radeontop)

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

    # Font defaults - will be computed based on systemStable in flake-base.nix
    # This is just a placeholder
    fonts = [ ];

    # System defaults
    swapFileEnable = false;
    swapFileSyzeGB = 32;
    downloadBufferSize = "134217728";
    systemStateVersion = "24.11";
    systemStable = false;

    # Update defaults
    autoSystemUpdateEnable = true;
    autoSystemUpdateDescription = "Auto Update System service";
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoSystemUpdate.sh";
    autoSystemUpdateUser = "root";
    autoSystemUpdateTimerDescription = "Auto Update System timer";
    autoSystemUpdateOnCalendar = "06:00:00";
    autoSystemUpdateCallNext = [ "autoUserUpdate.service" ];

    autoUserUpdateEnable = true;
    autoUserUpdateDescription = "Auto User Update";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "akunito";

    # Profile install invocation (used by Waybar update button)
    # Each profile should override this with the exact install.sh invocation for that profile.
    # Example: "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK -s"
    installCommand = "";

    # System packages - empty by default, profiles specify their own
    systemPackages = [ ];

    # Background package - handled in flake-base.nix with proper self reference
    # Profiles can override this if needed
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

    # Tailscale
    tailscaleEnabled = false;

    # ZSH prompt defaults
    zshinitContent = ''
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
  };
}
