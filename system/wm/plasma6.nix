{ pkgs, lib, userSettings, systemSettings, ... }:

{
  # CRITICAL: imports must be at top level, NOT inside lib.mkMerge or lib.mkIf
  # NixOS needs to resolve imports before evaluating conditions
  imports = [
    # ./wayland.nix
    ./pipewire.nix
    ./fonts.nix
    ./dbus.nix
    ../dm/sddm.nix  # Shared SDDM configuration (KWallet PAM)
    ./keyd.nix  # Keyboard remapping (Caps Lock to Hyper)
    # ./gnome-keyring.nix
    # ./hyprland.nix  <-- REMOVED: Plasma should not import Hyprland
    # Hyprland should be imported separately at the profile level if wmEnableHyprland is true
  ];
} // lib.mkMerge [
  {

    # # Security
    # security = {
    #   pam.services.login.enableGnomeKeyring = true;
    # };
    # services.gnome.gnome-keyring.enable = true;

    # # KDE Plasma 6
    # Apply conditions ONLY to configuration options, not imports
    # Allow coexistence with SwayFX - SDDM will show both sessions
    services.displayManager.sddm = lib.mkIf (userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) {
      enable = true;
      wayland.enable = true; # enable if blackscreen with plasma6
      # enableHidpi = true; # Enable if using high-DPI displays
    };
    
    # Default to Plasma unless Sway is enabled for DESK (in which case Sway takes precedence)
    services.displayManager.defaultSession = lib.mkIf (userSettings.wm == "plasma6" && !(systemSettings.enableSwayForDESK or false)) "plasma";
    
    services.desktopManager.plasma6 = lib.mkIf (userSettings.wm == "plasma6") {
      enable = true;
    };
 
    # # Enable the X11 windowing system.
    # # You can disable this if you're only using the Wayland session.
    # CRITICAL FIX: XWayland requires XKB keyboard layout configuration to start correctly.
    # Without it, XWayland apps (like LACT) may crash on launch or hang.
    services.xserver = lib.mkIf (userSettings.wm == "plasma6") {
      enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };
    programs.xwayland.enable = lib.mkIf (userSettings.wm == "plasma6") true;
  }

  # Use patched Breeze SDDM theme (controlled by sddmBreezePatchedTheme flag)
  # Helps with password focus stability on multi-monitor setups
  (lib.mkIf ((userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) && systemSettings.sddmBreezePatchedTheme) {
    environment.systemPackages = [
      (import ../dm/sddm-breeze-patched-theme.nix { inherit pkgs; })
    ];

    # IMPORTANT: Use X11 greeter when setup script is enabled (xrandr doesn't work with Wayland greeter)
    services.displayManager.sddm.wayland.enable = lib.mkIf (systemSettings.sddmSetupScript != null) (lib.mkForce false);

    services.displayManager.sddm.settings = {
      Theme = {
        Current = "breeze-patched";
      };
    };
  })
  
  # SDDM setup script for monitor configuration (controlled by sddmSetupScript flag)
  # This runs BEFORE SDDM shows the session selector, so it applies to both Plasma and SwayFX sessions
  # Set sddmSetupScript in profile config to a script string for custom monitor rotation/configuration
  # Example use case: Rotate portrait monitors before SDDM login screen appears
  (lib.mkIf ((userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) && systemSettings.sddmSetupScript != null) {
    services.displayManager.sddm.setupScript = systemSettings.sddmSetupScript;
  })
  
  # SDDM overlay to patch Login.qml for password field focus (DESK profile only)
  # NOTE: Overlays must be applied at flake level, not in modules
  # This is a placeholder - overlay will be moved to flake-base.nix or flake.nix
  # Keeping here for reference but it won't work in a module
  # (lib.mkIf (systemSettings.hostname == "nixosaku") {
  #   nixpkgs.overlays = [
  #     (final: prev: {
  #       # Patch SDDM to add focus: true to password field in Login.qml
  #       sddm = prev.sddm.overrideAttrs (oldAttrs: {
  #         postPatch = (oldAttrs.postPatch or "") + ''
  #           # Patch Login.qml to add focus: true to password TextField
  #           # Find Login.qml files in the breeze theme
  #           for qmlfile in $(find . -path "*/themes/breeze*" -name "Login.qml" 2>/dev/null); do
  #             # Check if file contains password field and doesn't already have focus: true
  #             if grep -q "echoMode: TextInput.Password" "$qmlfile" && ! grep -q "focus: true" "$qmlfile"; then
  #               # Add focus: true after echoMode line (with proper indentation)
  #               sed -i '/echoMode: TextInput.Password/a\                focus: true' "$qmlfile"
  #             fi
  #           done
  #         '';
  #       });
  #     })
  #   ];
  # })
]