# LAPTOP_X13 Profile Configuration (nixosx13aku)
# ThinkPad X13 Gen 2 AMD — replaces LAPTOP_L15
# Inherits from LAPTOP-base.nix with machine-specific overrides

let
  base = import ./LAPTOP-base.nix;
  # Import secrets for database credentials
  secrets = import ../secrets/domains.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "nixosx13aku";
    profile = "personal";
    envProfile = "LAPTOP_X13"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_X13 -s -u";
    gpuType = "amd";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [ ];

    # Security
    fuseAllowOther = false;
    pkiCertificates = [ ];
    # GUI askpass: popup password dialog when sudo has no terminal (e.g., Claude Code)
    sudoAskpassEnable = true;
    sudoTimestampTimeoutMinutes = 180;

    # SSH agent sudo authentication
    # Allows passwordless sudo when connected via SSH with agent forwarding (-A)
    # Local sessions without SSH agent still require password
    sshAgentSudoEnable = true;

    # Backups
    homeBackupEnable = true;
    homeBackupOnCalendar = "0/6:00:00";
    homeBackupCallNextEnabled = false;
    nfsBackupEnable = true;

    # Network
    ipAddress = "192.168.8.92";
    wifiIpAddress = "192.168.8.93";
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    resolvedEnable = false;

    # Firewall
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # NFS nofail safety net (prevents boot hang when TrueNAS is unreachable)
    disk3_enabled = true;
    disk3_name = "/mnt/NFS_media";
    disk3_device = "192.168.20.200:/mnt/hddpool/media";
    disk3_fsType = "nfs4";
    disk3_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk4_enabled = true;
    disk4_name = "/mnt/NFS_emulators";
    disk4_device = "192.168.20.200:/mnt/ssdpool/emulators";
    disk4_fsType = "nfs4";
    disk4_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk5_enabled = true;
    disk5_name = "/mnt/NFS_library";
    disk5_device = "192.168.20.200:/mnt/ssdpool/library";
    disk5_fsType = "nfs4";
    disk5_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
    disk8_enabled = true;
    disk8_name = "/mnt/NFS_Backups";
    disk8_device = "192.168.20.200:/mnt/hddpool/workstation_backups";
    disk8_fsType = "nfs4";
    disk8_options = [
      "nofail"
      "x-systemd.device-timeout=5s"
    ];

    # NFS client
    nfsClientEnable = true;
    nfsMounts = [
      {
        what = "192.168.20.200:/mnt/hddpool/media";
        where = "/mnt/NFS_media";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/library";
        where = "/mnt/NFS_library";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/emulators";
        where = "/mnt/NFS_emulators";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.20.200:/mnt/hddpool/workstation_backups";
        where = "/mnt/NFS_Backups";
        type = "nfs";
        options = "noatime";
      }
    ];
    nfsAutoMounts = [
      {
        where = "/mnt/NFS_media";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_library";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_emulators";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_Backups";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
    ];

    # SSH
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # Printer
    servicePrinting = true;
    networkPrinters = true;

    # Lid behavior: managed by swaySmartLidEnable (from LAPTOP-base.nix)
    # Power button: suspend (from LAPTOP-base.nix)
    # Logind lid settings: "ignore" (handled by Sway bindswitch)

    # Sleep mode: AMD Zen 3 X13 Gen 2 supports s2idle
    MEM_SLEEP_ON_AC = "s2idle";
    MEM_SLEEP_ON_BAT = "s2idle";

    # LUKS UUID of encrypted swap partition (set after NixOS install on X13)
    hibernateSwapLuksUUID = null;

    # Suspend/resume debug instrumentation
    suspendDebugEnable = true;

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      # No additional LAPTOP_X13-specific packages needed - all in modules
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Desktop Environment ===
    enableSwayForDESK = false; # Not needed when wm = "sway" (no dual-WM setup)

    # === Package Modules ===
    systemBasicToolsEnable = true; # Basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = true; # Advanced networking tools (nmap, traceroute, dnsutils, etc.)

    # === Hardware Optimizations ===
    thinkpadEnable = true; # Enable Lenovo Thinkpad hardware optimizations
    thinkpadModel = "lenovo-thinkpad-x13-amd"; # X13 Gen 2 AMD
    thunderboltEnable = false; # X13 AMD has no Thunderbolt
    amdPstateEnable = true; # AMD P-State EPP driver (Zen 3)
    fprintdEnable = true; # Fingerprint reader support

    # === System Services & Features ===
    sunshineEnable = true; # Enable Sunshine game streaming
    xboxControllerEnable = true; # Enable Xbox controller support (xpadneo)

    # === SSH Configuration ===
    sshHostsManaged = true; # Nix-managed ~/.ssh/config (shared SSH host definitions)

    # === Development Tools & AI ===
    developmentToolsEnable = true; # Enable development IDEs and cloud tools
    aichatEnable = true; # Enable aichat CLI tool with OpenRouter support
    nixvimEnabled = true; # Enable NixVim configuration (Cursor IDE-like experience)

    # === Control Panel ===
    controlPanelEnable = true; # Enable NixOS infrastructure control panel

    # === Tailscale Mesh VPN ===
    tailscaleEnable = true; # Enable daemon (but don't auto-connect - manual via Trayscale GUI)
    # trayscaleGuiEnable inherited from LAPTOP-base.nix (true)
    tailscaleLoginServer = "https://${secrets.headscaleDomain}"; # Self-hosted Headscale
    tailscaleAcceptRoutes = false; # Accept routes (already on LAN)
    tailscaleAcceptDns = false; # Don't override DNS (use pfSense directly)

    # === Database Client Credentials ===
    # Generate ~/.pgpass, ~/.my.cnf, ~/.redis-credentials for CLI tools and DBeaver
    dbCredentialsEnable = true;
    dbCredentialsHost = "192.168.8.103"; # LXC_database server
    dbCredentialsPostgres = [
      { database = "plane"; user = "plane"; password = secrets.dbPlanePassword; }
      { database = "rails_database_prod"; user = "liftcraft"; password = secrets.dbLiftcraftPassword; }
    ];
    dbCredentialsMariadb = [
      { database = "nextcloud"; user = "nextcloud"; password = secrets.dbNextcloudPassword; }
    ];
    dbCredentialsRedisPassword = secrets.redisServerPassword;
  };

  userSettings = base.userSettings // {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";
    wm = "sway"; # Switched from plasma6 for Sway-only setup (no KDE compilation)

    # Different theme for YOGAAKU
    theme = "ashes";

    dockerEnable = true;
    virtualizationEnable = false;
    qemuGuestAddition = false; # VM

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      # LAPTOP_X13-specific packages

      # NOTE: vivaldi is provided by user/app/browser/vivaldi.nix module (with KWallet support)
      # NOTE: Development tools in user/app/development/development.nix (controlled by developmentToolsEnable flag)
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) ===
    userBasicPkgsEnable = true; # Basic user packages (browsers, office, communication, etc.)
    userAiPkgsEnable = false; # AI & ML packages (lmstudio, ollama-rocm)
    rangerFullPreviewEnable = true; # Full ranger preview (fonts, ebooks, spreadsheets, etc.)

    # Different prompt color for LAPTOP
    zshinitContent = ''
      # Keybindings for Home/End/Delete keys
      bindkey '\e[1~' beginning-of-line     # Home key
      bindkey '\e[4~' end-of-line           # End key
      bindkey '\e[3~' delete-char           # Delete key

      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';
  };
}
