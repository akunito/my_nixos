# LAPTOP Profile Configuration (nixolaptopaku)
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
    hostname = "nixolaptopaku";
    profile = "personal";
    envProfile = "LAPTOP_L15"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_L15 -s -u";
    gpuType = "intel";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [ ];

    # Security
    fuseAllowOther = false;
    pkiCertificates = [ /home/akunito/.myCA/ca.cert.pem ];
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
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
    ];

    # Printer
    servicePrinting = true;
    networkPrinters = true;

    # Lid behavior: managed by swaySmartLidEnable (from LAPTOP-base.nix)
    # Power button: suspend (from LAPTOP-base.nix)
    # Logind lid settings: "ignore" (handled by Sway bindswitch)

    # Sleep mode: Tiger Lake L15 Gen 2 only supports s2idle (no S3 deep sleep)
    MEM_SLEEP_ON_AC = "s2idle";
    MEM_SLEEP_ON_BAT = "s2idle";

    # Suspend/resume debug instrumentation
    suspendDebugEnable = true;

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      # No additional LAPTOP_L15-specific packages needed - all in modules
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
    thinkpadModel = "lenovo-thinkpad-l14-intel"; # L15 → L14 Intel (closest match)
    thunderboltEnable = true; # Enable Thunderbolt dock/device support (OWC dock + 10GbE adapter)

    # === System Services & Features ===
    sunshineEnable = true; # Enable Sunshine game streaming
    xboxControllerEnable = true; # Enable Xbox controller support (xpadneo)

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
      # LAPTOP_L15-specific packages
      
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
