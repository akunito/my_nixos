{ pkgs, lib, userSettings, systemSettings, ... }:

lib.mkMerge [
  {
    # Import wayland config
    imports = [ # ./wayland.nix
                ./pipewire.nix
                ./fonts.nix
                ./dbus.nix
                #./gnome-keyring.nix
              ]
      ++ lib.optional userSettings.wmEnableHyprland (./. + "/hyprland.nix");

    # # Security
    # security = {
    #   pam.services.login.enableGnomeKeyring = true;
    # };
    # services.gnome.gnome-keyring.enable = true;

    # # KDE Plasma 6
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm.wayland.enable = true; # enable if blackscreen with plasma6
    # services.displayManager.sddm.enableHidpi = true; # Enable if using high-DPI displays
    services.displayManager.defaultSession = "plasma";
 
    # # Enable the X11 windowing system.
    # # You can disable this if you're only using the Wayland session.
    services.xserver.enable = true;
    programs.xwayland.enable = true;
  }
  
  # SDDM setup script for monitor rotation (DESK profile only)
  # Rotates the NSL DP-2-RGB-27QHDS monitor to portrait (right) orientation
  # Uses EDID/model name matching instead of port identifier for reliability
  # Only enabled on DESK system (hostname: nixosaku) to avoid unnecessary execution on other systems
  (lib.mkIf (systemSettings.hostname == "nixosaku") {
    services.displayManager.sddm.setupScript = ''
      # Safe rotation script
      # First, ensure all monitors are detected and enabled (wake up sleeping monitors)
      ${pkgs.xorg.xrandr}/bin/xrandr --auto
      
      # Get the port name for the NSL monitor by grepping full properties
      # Note: This looks for the output associated with the model name
      
      # Method: Use --props to get EDID info, then grep backwards to find port
      # The grep -B 20 looks 20 lines "Back" from where it finds the monitor name
      # to find the port identifier line (e.g., "DP-1 connected")
      MONITOR=$(${pkgs.xorg.xrandr}/bin/xrandr --props | grep -B 20 "27QHDS" | grep "^[A-Z]" | head -n 1 | cut -d' ' -f1)
      
      if [ ! -z "$MONITOR" ]; then
          ${pkgs.xorg.xrandr}/bin/xrandr --output "$MONITOR" --rotate right
      fi
    '';
  })
]