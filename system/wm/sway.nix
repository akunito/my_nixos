{
  pkgs,
  lib,
  userSettings,
  systemSettings,
  ...
}:

let
  # Helper: is Sway enabled (either as primary WM or as dual-WM with Plasma)
  swayEnabled = userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true;
in
{
  # Import shared dependencies
  imports = [
    ./wayland.nix
    ./pipewire.nix
    ./fonts.nix
    ./dbus.nix
    ../dm/sddm.nix # Shared SDDM configuration (KWallet PAM) - used by non-greetd profiles
    ../dm/greetd.nix # greetd + ReGreet configuration - modern Wayland-native display manager
    ./keyd.nix # Keyboard remapping (Caps Lock to Hyper)
  ];

  # CRITICAL: Use swayfx instead of standard sway
  programs.sway = lib.mkIf swayEnabled {
    enable = true;
    package = pkgs.swayfx; # Use SwayFX for blur, shadows, rounded corners
    extraPackages = with pkgs; [
      swaylock-effects # Elegant lock screen with blurred screenshot
      swayidle # Idle daemon for screen locking
      xwayland # XWayland support for compatibility
    ];
  };

  # Display Manager configuration
  # greetd is configured in ../dm/greetd.nix (enabled via systemSettings.greetdEnable)
  # SDDM is configured below for profiles that don't use greetd
  services.displayManager.sddm = lib.mkIf (swayEnabled && !(systemSettings.greetdEnable or false)) (lib.mkMerge [
    # Base SDDM settings
    {
      enable = true;
      # Weston (SDDM Wayland compositor) fails on multi-monitor setups — use X11 greeter
      wayland.enable = false;
    }
    # Astronaut theme (Qt6 modern theme for all Sway profiles without breeze-patched)
    # All Qt6 deps MUST be in extraPackages — SDDM greeter only sees packages wired through wrapQtAppsHook
    (lib.mkIf (!(systemSettings.sddmBreezePatchedTheme or false)) {
      theme = "sddm-astronaut-theme";
      extraPackages = [
        pkgs.sddm-astronaut
        pkgs.kdePackages.qtmultimedia
      ];
      settings = {
        Users = {
          # Hide system/wrapper users from login screen
          HideUsers = "restic";
        };
      };
    })
    # Breeze-patched theme configuration (legacy - requires Plasma dependencies)
    (lib.mkIf (systemSettings.sddmBreezePatchedTheme or false) {
      settings = {
        Theme = {
          Current = "breeze-patched";
        };
      };
    })
    # Setup script for monitor configuration (e.g., portrait rotation)
    (lib.mkIf ((systemSettings.sddmSetupScript or null) != null) {
      setupScript = systemSettings.sddmSetupScript;
    })
  ]);

  # Set Sway as default session for display manager
  services.displayManager.defaultSession = lib.mkIf swayEnabled "sway";

  # SDDM theme packages (must be in systemPackages for theme files to land in /run/current-system/sw/share/sddm/themes/)
  environment.systemPackages = lib.mkIf swayEnabled (
    if (systemSettings.sddmBreezePatchedTheme or false)
    then [
      (import ../dm/sddm-breeze-patched-theme.nix { inherit pkgs; })
    ]
    else if !(systemSettings.greetdEnable or false)
    then [
      pkgs.sddm-astronaut
    ]
    else []
  );

  # CRITICAL: Force Electron apps to native Wayland mode
  # This must be at system level because extraSessionCommands don't reliably propagate to all processes
  environment.variables = lib.mkMerge [
    # Base Wayland settings for all GPUs
    (lib.mkIf swayEnabled {
      NIXOS_OZONE_WL = "1";
    })
    # AMD-specific: Vulkan ICD paths and driver selection (fixes Lutris "Found no drivers" error)
    (lib.mkIf (swayEnabled && systemSettings.gpuType == "amd") {
      VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json:/run/opengl-driver-32/share/vulkan/icd.d/radeon_icd.i686.json";
      AMD_VULKAN_ICD = "RADV"; # Force RADV over any AMDVLK if installed
    })
  ];

  # CRITICAL: xdg-desktop-portal-wlr systemd service
  # The xdg.portal.wlr.enable option doesn't create the service properly
  # We need to manually create the systemd user service
  systemd.user.services.xdg-desktop-portal-wlr = lib.mkIf swayEnabled {
    description = "Portal service (wlroots implementation)";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "dbus";
      BusName = "org.freedesktop.impl.portal.desktop.wlr";
      # Clear any existing ExecStart first (from overrides.conf), then set ours
      ExecStart = [
        "" # This clears the existing ExecStart
        "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr"
      ];
      Restart = "on-failure";
    };
  };

  # Polkit authentication agent (needed for GUI admin apps)
  security.polkit.enable = lib.mkIf swayEnabled true;

  # Polkit-gnome authentication agent
  systemd.user.services.polkit-gnome-authentication-agent-1 = lib.mkIf swayEnabled {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # XWayland support for compatibility
  programs.xwayland.enable = lib.mkIf swayEnabled true;

  # KWallet PAM integration for Sway-specific screen unlock
  # Note: login and sddm KWallet settings are now handled by ../dm/sddm.nix
  security.pam.services = lib.mkIf swayEnabled {
    swaylock.enableKwallet = true; # Unlock wallet on screen unlock (Sway-specific)
  };

  # TODO: Remove later - GNOME Keyring removed in favor of KWallet to prevent conflicts
  # GNOME Keyring for Vivaldi and other apps that need secure credential storage
  # services.gnome.gnome-keyring.enable = lib.mkIf swayEnabled true;
  # security.pam.services.login.enableGnomeKeyring = lib.mkIf swayEnabled true;

  # Keyboard input configuration for polyglot typing (English/Spanish)
  # This will be configured in the Sway config file, but we ensure xkb is available
  # Use mkForce to override the variant from wayland.nix when Sway is enabled
  services.xserver = lib.mkIf swayEnabled {
    enable = true;
    xkb = {
      layout = "us";
      variant = lib.mkForce "altgr-intl"; # US International (AltGr Dead Keys) for English/Spanish hybrid
    };
  };
}
