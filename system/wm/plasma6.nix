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
  # Uses EDID/model name matching with fallback to port identifier (DP-2)
  # Only enabled on DESK system (hostname: nixosaku) to avoid unnecessary execution on other systems
  (lib.mkIf (systemSettings.hostname == "nixosaku") {
    services.displayManager.sddm.setupScript = ''
      # Redirect all output to log file for debugging
      exec >/tmp/sddm-rotation.log 2>&1
      set -x  # Enable verbose mode to see all commands
      
      echo "=== SDDM Monitor Rotation Script Started ==="
      echo "Timestamp: $(date)"
      
      # Use absolute path - SDDM user has empty PATH
      XRANDR=${pkgs.xorg.xrandr}/bin/xrandr
      
      # First, ensure all monitors are detected and enabled (wake up sleeping monitors)
      echo "Waking up monitors..."
      $XRANDR --auto
      sleep 1
      
      # Try to detect monitor with multiple patterns
      MONITOR=""
      PATTERNS=("27QHDS" "NSL.*RGB" "RGB-27QHDS" "NSL")
      
      echo "Attempting to detect NSL RGB-27QHDS monitor..."
      for pattern in "''${PATTERNS[@]}"; do
        echo "Trying pattern: $pattern"
        # Method: Use --props to get EDID info, then grep backwards to find port
        # The grep -B 20 looks 20 lines "Back" from where it finds the monitor name
        # to find the port identifier line (e.g., "DP-1 connected")
        MONITOR=$($XRANDR --props 2>/dev/null | grep -B 20 "$pattern" | grep "^[A-Z]" | head -n 1 | cut -d' ' -f1)
        
        if [ ! -z "$MONITOR" ]; then
          echo "Monitor detected via pattern '$pattern': $MONITOR"
          break
        else
          echo "Pattern '$pattern' did not match any monitor"
        fi
      done
      
      # Fallback to DP-2 if detection failed
      if [ -z "$MONITOR" ]; then
        echo "EDID detection failed, using fallback: DP-2"
        MONITOR="DP-2"
      fi
      
      # Rotate the monitor (90 degrees clockwise = portrait right)
      echo "Rotating monitor $MONITOR to portrait (right)..."
      if $XRANDR --output "$MONITOR" --rotate right; then
        echo "Rotation successful for $MONITOR"
        # Small delay to let SDDM stabilize after monitor rotation
        sleep 0.5
      else
        echo "ERROR: Rotation failed for $MONITOR"
        # List all available outputs for debugging
        echo "Available outputs:"
        $XRANDR --query | grep " connected" || echo "No connected outputs found"
      fi
      
      echo "=== SDDM Monitor Rotation Script Completed ==="
    '';
  })
]