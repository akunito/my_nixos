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
  # This runs BEFORE SDDM shows the session selector, so it applies to both Plasma and SwayFX sessions
  # Rotates the NSL DP-2-RGB-27QHDS monitor to portrait (90 degrees, right orientation)
  # Uses EDID/model name matching with fallback to port identifier (DP-2)
  # Only enabled on DESK system (hostname: nixosaku) to avoid unnecessary execution on other systems
  (lib.mkIf ((userSettings.wm == "plasma6" || systemSettings.enableSwayForDESK == true) && systemSettings.hostname == "nixosaku") {
    services.displayManager.sddm.setupScript = ''
      # Redirect all output to log file for debugging
      # #region agent log
      LOGFILE="/tmp/sddm-rotation.log"
      exec >"$LOGFILE" 2>&1
      set -x  # Enable verbose mode to see all commands
      
      echo "=== SDDM Monitor Rotation Script Started ==="
      echo "Timestamp: $(date)"
      echo "Hostname check: $(hostname)"
      echo "XRANDR path will be: ${pkgs.xorg.xrandr}/bin/xrandr"
      
      # Test if xrandr binary exists
      XRANDR="${pkgs.xorg.xrandr}/bin/xrandr"
      if [ ! -f "$XRANDR" ]; then
        echo "ERROR: xrandr binary not found at $XRANDR"
        echo "Attempting to find xrandr in system..."
        which xrandr || echo "xrandr not in PATH"
        exit 1
      fi
      echo "xrandr binary found: $XRANDR"
      echo "xrandr version: $($XRANDR --version 2>&1 || echo 'version check failed')"
      
      # First, ensure all monitors are detected and enabled (wake up sleeping monitors)
      echo "Waking up monitors..."
      if ! $XRANDR --auto; then
        echo "ERROR: xrandr --auto failed"
      fi
      sleep 1
      
      # Dump full xrandr output for debugging
      echo "=== Full xrandr --query output ==="
      $XRANDR --query 2>&1 || echo "xrandr --query failed"
      echo "=== Full xrandr --props output ==="
      $XRANDR --props 2>&1 | head -100 || echo "xrandr --props failed (showing first 100 lines)"
      
      # Try to detect monitor with multiple patterns
      MONITOR=""
      PATTERNS=("27QHDS" "NSL.*RGB" "RGB-27QHDS" "NSL")
      
      echo "Attempting to detect NSL RGB-27QHDS monitor..."
      for pattern in "''${PATTERNS[@]}"; do
        echo "Trying pattern: $pattern"
        # Method: Use --props to get EDID info, then grep backwards to find port
        # The grep -B 20 looks 20 lines "Back" from where it finds the monitor name
        # to find the port identifier line (e.g., "DP-1 connected")
        PROPS_OUTPUT=$($XRANDR --props 2>&1)
        echo "Pattern search in props output (first 200 chars): $(echo "$PROPS_OUTPUT" | head -c 200)"
        MONITOR=$(echo "$PROPS_OUTPUT" | grep -B 20 "$pattern" | grep "^[A-Z]" | head -n 1 | cut -d' ' -f1)
        
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
      
      # Verify monitor exists before rotating
      echo "Checking if monitor $MONITOR exists..."
      if $XRANDR --query | grep -q "^$MONITOR"; then
        echo "Monitor $MONITOR found in xrandr output"
      else
        echo "WARNING: Monitor $MONITOR not found in xrandr --query output"
        echo "Available monitors:"
        $XRANDR --query | grep " connected" || echo "No connected outputs found"
      fi
      
      # Rotate the monitor (90 degrees clockwise = portrait right)
      echo "Rotating monitor $MONITOR to portrait (right)..."
      ROTATE_OUTPUT=$($XRANDR --output "$MONITOR" --rotate right 2>&1)
      ROTATE_EXIT=$?
      echo "Rotation command exit code: $ROTATE_EXIT"
      echo "Rotation command output: $ROTATE_OUTPUT"
      
      if [ $ROTATE_EXIT -eq 0 ]; then
        echo "Rotation successful for $MONITOR"
        # Verify rotation
        CURRENT_ROTATION=$($XRANDR --query | grep "^$MONITOR" | grep -o "right\|left\|inverted\|normal" | head -1)
        echo "Current rotation for $MONITOR: $CURRENT_ROTATION"
        # Small delay to let SDDM stabilize after monitor rotation
        sleep 0.5
      else
        echo "ERROR: Rotation failed for $MONITOR (exit code: $ROTATE_EXIT)"
        # List all available outputs for debugging
        echo "Available outputs:"
        $XRANDR --query | grep " connected" || echo "No connected outputs found"
      fi
      
      echo "=== SDDM Monitor Rotation Script Completed ==="
      # #endregion
    '';
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