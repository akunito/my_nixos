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
    envProfile = "LAPTOP_AGA"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LAPTOP_AGA -s -u";
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

    # Network
    ipAddress = "192.168.0.77";
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
    tailscaleAcceptRoutes = true; # Accept routes from subnet router

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
      pkgs-unstable.vivaldi # AGA-specific browser

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
