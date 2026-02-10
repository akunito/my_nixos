# YOGAAKU Profile Configuration
# Inherits from LAPTOP-base.nix with machine-specific overrides (older Lenovo Yoga laptop)

let
  base = import ./LAPTOP-base.nix;
  secrets = import ../secrets/domains.nix;
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "nixosyogaaku";
    profile = "personal";
    envProfile = "LAPTOP_YOGAAKU"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_YOGAAKU -s -u";
    bootMode = "bios";
    grubDevice = "/dev/nvme0n1"; # BIOS boot on NVMe (Samsung MZVLB256HBHQ)
    grubEnableCryptodisk = true; # Enable GRUB cryptodisk support for encrypted disk (LUKS)
    gpuType = "intel";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [
      "cpufreq_powersave"
      "xpadneo" # xbox controller
    ];

    # Security
    fuseAllowOther = false;
    # pkiCertificates = [ /home/akunito/.certificates/ca.cert.pem ];
    sudoTimestampTimeoutMinutes = 180;

    # Backups - disabled on this machine
    homeBackupEnable = false;

    # Network
    ipAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    wifiIpAddress = "192.168.8.xxx"; # ip to be reserved on router by mac (manually)
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    resolvedEnable = false;

    # Firewall
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];

    # NFS client - disabled by default on this machine
    nfsClientEnable = false;
    nfsMounts = [
      {
        what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Books";
        where = "/mnt/NFS_Books";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/downloads";
        where = "/mnt/NFS_downloads";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Media";
        where = "/mnt/NFS_Media";
        type = "nfs";
        options = "noatime";
      }
      {
        what = "192.168.8.80:/mnt/DATA_4TB/backups/akunitoLaptop";
        where = "/mnt/NFS_Backups";
        type = "nfs";
        options = "noatime";
      }
    ];
    nfsAutoMounts = [
      {
        where = "/mnt/NFS_Books";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_Media";
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

    # Printer - disabled on this machine
    servicePrinting = false;
    networkPrinters = false;

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      # YOGAAKU-specific packages
      pkgs.tldr
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
    thinkpadModel = "lenovo-thinkpad-x280"; # X380 Yoga → X280 (same generation)

    # === System Services & Features ===
    sambaEnable = false; # Disable Samba file sharing
    sunshineEnable = false; # Disable Sunshine game streaming (older machine)
    xboxControllerEnable = true; # Enable Xbox controller support (xpadneo)

    # === Tailscale Mesh VPN ===
    tailscaleEnable = true; # Enable daemon (but don't auto-connect - manual via Trayscale GUI)
    # trayscaleGuiEnable inherited from LAPTOP-base.nix (true)
    tailscaleLoginServer = "https://${secrets.headscaleDomain}"; # Self-hosted Headscale
    tailscaleAcceptRoutes = false; # Accept routes (already on LAN)
    tailscaleAcceptDns = false; # Don't override DNS (use pfSense directly)

    # === Development Tools ===
    developmentToolsEnable = true; # Enable development IDEs and cloud tools

    # === Features Disabled (older machine) ===
    starCitizenModules = false; # Disable Star Citizen optimizations
    vivaldiPatch = false; # Disable Vivaldi patches

    # Fonts: use default computation in flake-base.nix
    # (nerdfonts/powerline for stable, nerd-fonts.jetbrains-mono for unstable)
  };

  userSettings = base.userSettings // {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";
    wm = "sway"; # Switched from plasma6 for Sway-only setup (no KDE compilation)

    # Different theme for YOGAAKU
    theme = "ashes";

    dockerEnable = false;
    virtualizationEnable = true;
    qemuGuestAddition = true; # VM

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      # No additional YOGAAKU-specific packages
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
