# LAPTOP_AGA Profile Configuration (nixosaga)
# Inherits from LAPTOP-base.nix with machine-specific overrides

let
  base = import ./LAPTOP-base.nix;
  # Headscale domain is public, no need for git-crypt on this machine
  headscaleDomain = "headscale.akunito.com";
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    hostname = "nixosaga";
    profile = "personal";
    envProfile = "LAPTOP_A"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_A -s -u";
    gpuType = "intel";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [
      "cpufreq_powersave"
    ];

    # Sway/SwayFX - Override base (AGA uses plasma6 only)
    enableSwayForDESK = false; # Disable Sway (AGA uses plasma6 only)
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

    # Network
    ipAddress = "192.168.8.77"; # or .78 depending on wifi/eth (pfSense DHCP)
    wifiIpAddress = "192.168.0.78";
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

    # Printer
    servicePrinting = false;
    networkPrinters = false;

    # Power management - Lid behavior (suspend on close)
    lidSwitch = "suspend";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    powerKey = "suspend";

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      # AGA-specific packages
      pkgs.tldr

      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Package Modules ===
    systemBasicToolsEnable = true; # Basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = true; # Advanced networking tools (nmap, traceroute, dnsutils, etc.)

    # === Hardware Optimizations ===
    thinkpadEnable = true; # Enable Lenovo Thinkpad hardware optimizations
    thinkpadModel = "lenovo-thinkpad-t490"; # T580 → T490 (next generation, same family)
    thunderboltEnable = true; # Enable Thunderbolt dock/device support (TB3 port)

    # === Intel GPU & Thermal Power Tuning (T490 = 8th gen Intel UHD 620) ===
    intelGpuFbcEnable = true; # i915 framebuffer compression
    intelGpuPsrEnable = true; # i915 panel self-refresh
    thermaldEnable = true; # Intel thermal daemon

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
    aichatEnable = false; # Disable aichat CLI tool

    # === Other Features ===
    starCitizenModules = false; # Disable Star Citizen optimizations
    vivaldiPatch = true; # Enable Vivaldi patches

    # Auto update - DISABLED (unstable profile)
    # Custom paths kept for reference if manually enabled
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
      # AGA-specific packages
      pkgs-unstable.kdePackages.kcalc # AGA-specific calculator
      # NOTE: Vivaldi is added by user/app/browser/vivaldi.nix with KWallet wrapper

      # NOTE: Development tools in user/app/development/development.nix (controlled by developmentToolsEnable flag)
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
