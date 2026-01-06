{ pkgs, lib, userSettings, systemSettings, ... }:

{
  # CRITICAL: imports must be at top level, NOT inside lib.mkMerge or lib.mkIf
  # NixOS needs to resolve imports before evaluating conditions
  imports = [
    # ./wayland.nix
    ./pipewire.nix
    ./fonts.nix
    ./dbus.nix
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
    
    # Default to Plasma unless user selects SwayFX at login
    services.displayManager.defaultSession = lib.mkIf (userSettings.wm == "plasma6") "plasma";
    
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
  
  # SDDM setup script for monitor rotation (DESK profile only)
  # Rotates the NSL DP-2-RGB-27QHDS monitor to portrait (90 degrees, right orientation)
  # Uses EDID/model name matching instead of port identifier for reliability
  # Only enabled on DESK system (hostname: nixosaku) to avoid unnecessary execution on other systems
  (lib.mkIf (systemSettings.hostname == "nixosaku") {
    services.displayManager.sddm.setupScript = ''
      # Safe rotation script with retry logic for slow monitor detection
      # First, ensure all monitors are detected and enabled (wake up sleeping monitors)
      ${pkgs.xorg.xrandr}/bin/xrandr --auto
      
      # Wait a moment for monitors to be fully detected (especially important for slower monitors)
      sleep 1
      
      # Retry logic: Try to find the monitor up to 5 times with 1 second delays
      # This handles cases where the monitor takes longer to activate
      MONITOR=""
      MAX_RETRIES=5
      RETRY_COUNT=0
      
      while [ -z "$MONITOR" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Get the port name for the NSL monitor by grepping full properties
        # Method: Use --props to get EDID info, then grep backwards to find port
        # The grep -B 20 looks 20 lines "Back" from where it finds the monitor name
        # to find the port identifier line (e.g., "DP-1 connected")
        MONITOR=$(${pkgs.xorg.xrandr}/bin/xrandr --props 2>/dev/null | grep -B 20 "27QHDS" | grep "^[A-Z]" | head -n 1 | cut -d' ' -f1)
        
        if [ -z "$MONITOR" ]; then
          RETRY_COUNT=$((RETRY_COUNT + 1))
          if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            sleep 1
            # Try to wake up the monitor again
            ${pkgs.xorg.xrandr}/bin/xrandr --auto
          fi
        fi
      done
      
      # Rotate the monitor if found (90 degrees clockwise = portrait right)
      if [ ! -z "$MONITOR" ]; then
        ${pkgs.xorg.xrandr}/bin/xrandr --output "$MONITOR" --rotate right
        # Small delay to let SDDM stabilize after monitor rotation
        # This helps prevent focus loss when the monitor activates
        sleep 0.5
      fi
    '';
  })
]