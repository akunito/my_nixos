# LAPTOP_YOGA Profile Configuration (nixosyogaaga)
# Inherits from LAPTOP-base.nix with machine-specific overrides
# Hardware: Lenovo ThinkPad X380 Yoga (repurposed for user aga)

let
  base = import ./LAPTOP-base.nix;
  # Headscale domain is public, no need for git-crypt on this machine
  headscaleDomain = "headscale.akunito.com";
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "nixosyogaaga";
    profile = "personal";
    envProfile = "LAPTOP_YOGA"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_YOGA -s -u";
    bootMode = "bios";
    grubDevice = "/dev/nvme0n1"; # BIOS boot on NVMe (Samsung MZVLB256HBHQ)
    grubEnableCryptodisk = true; # Enable GRUB cryptodisk support for encrypted disk (LUKS)
    gpuType = "intel";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [
      "cpufreq_powersave"
    ];

    # Sway/SwayFX - Override base (YOGA uses plasma6 only)
    enableSwayForDESK = false; # Disable Sway (YOGA uses plasma6 only)
    swwwEnable = false;        # Disable Sway wallpaper daemon

    # Security
    fuseAllowOther = false;
    pkiCertificates = [ /home/aga/.certificates/ca.cert.pem ];

    # GUI askpass: popup password dialog when sudo has no terminal (e.g., Claude Code)
    sudoAskpassEnable = true;
    sudoTimestampTimeoutMinutes = 180;

    # SSH agent sudo authentication
    # Allows passwordless sudo when connected via SSH with agent forwarding (-A)
    # Local sessions without SSH agent still require password
    sshAgentSudoEnable = true;

    # SSH authorized keys (required for SSH agent sudo auth)
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # Backups - disabled on this machine
    homeBackupEnable = false;

    # Network
    ipAddress = "192.168.8.100"; # ip to be reserved on router by mac (manually)
    wifiIpAddress = "192.168.8.101"; # ip to be reserved on router by mac (manually)
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    resolvedEnable = false;

    # Firewall - sunshine ports
    allowedTCPPorts = [
      47984
      47989
      47990
      48010 # sunshine
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      8000
      8001
      8002
      8003
      8004
      8005
      8006
      8007
      8008
      8009
      8010 # sunshine
    ];

    # NFS client - disabled on this machine
    nfsClientEnable = false;

    # Printer - disabled on this machine
    servicePrinting = false;
    networkPrinters = false;

    # Power management - Lid behavior (suspend on close)
    lidSwitch = "suspend";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    powerKey = "suspend";

    # LUKS UUID of encrypted swap partition (from: sudo cryptsetup luksDump /dev/nvme0n1p2)
    hibernateSwapLuksUUID = "1fbdeb58-e07a-4c7b-81db-d72067ae12cb";

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      pkgs.tldr
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Package Modules ===
    systemBasicToolsEnable = true; # Basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = true; # Advanced networking tools (nmap, traceroute, dnsutils, etc.)

    # === Hardware Optimizations ===
    thinkpadEnable = true; # Enable Lenovo Thinkpad hardware optimizations
    thinkpadModel = "lenovo-thinkpad-x280"; # X380 Yoga → X280 (same generation)
    thunderboltEnable = false; # X380 Yoga has no Thunderbolt 3

    # Intel GPU power tuning (Intel UHD 620)
    intelGpuFbcEnable = true; # Framebuffer compression
    intelGpuPsrEnable = true; # Panel self-refresh

    # Intel thermal daemon (8th gen Kaby Lake R)
    thermaldEnable = true;

    # === System Services & Features ===
    sambaEnable = false; # Disable Samba file sharing
    sunshineEnable = true; # Enable Sunshine game streaming
    wireguardEnable = true; # Enable WireGuard VPN
    nextcloudEnable = true; # Enable Nextcloud client
    appImageEnable = false; # Disable AppImage support (override base)
    xboxControllerEnable = false; # Disable Xbox controller support

    # === Tailscale Mesh VPN ===
    tailscaleEnable = true; # Enable Tailscale client
    tailscaleLoginServer = "https://${headscaleDomain}"; # Self-hosted Headscale
    tailscaleAcceptRoutes = true; # Accept routes from subnet router (LAN access)
    tailscaleAcceptDns = true; # Accept DNS from Tailscale
    tailscaleLanAutoToggle = false; # Disabled - user controls manually
    tailscaleLanGateway = "192.168.8.1"; # Not used (auto-toggle disabled)
    tailscaleGuiAutostart = true; # Start trayscale GUI with Plasma 6

    # === Development Tools & AI ===
    developmentToolsEnable = false; # Disable development IDEs and cloud tools
    aichatEnable = false; # Disable aichat CLI tool

    # === Other Features ===
    starCitizenModules = false; # Disable Star Citizen optimizations
    vivaldiPatch = true; # Enable Vivaldi patches

    # Auto update - DISABLED (unstable profile)
    autoSystemUpdateEnable = false;
    autoUserUpdateEnable = false;
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoSystemUpdate.sh";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "aga";

    systemStable = false;
  };

  userSettings = base.userSettings // {
    username = "aga";
    name = "aga";
    email = "";
    dotfilesDir = "/home/aga/.dotfiles";

    # Theme inherited from base ("ashes")
    # wm, wmEnableHyprland, browser, term, font, etc. inherited from base

    dockerEnable = false;
    virtualizationEnable = true;
    qemuGuestAddition = false;

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      pkgs-unstable.kdePackages.kcalc # Calculator
      # NOTE: Vivaldi is added by user/app/browser/vivaldi.nix with KWallet wrapper
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) ===
    userBasicPkgsEnable = true; # Basic user packages (browsers, office, communication, etc.)
    userAiPkgsEnable = false; # AI & ML packages (lmstudio, ollama-rocm)

    # zshinitContent and sshExtraConfig inherited from base
  };
}
