{ config, pkgs, lib, userSettings, systemSettings, ... }:

let
  # Hyper key combination (Super+Ctrl+Alt)
  hyper = "Mod4+Control+Mod1";
  
  # DESK startup apps script - launches applications in specific workspaces after daemons are ready
  # CRITICAL: KWallet must be unlocked before ANY apps launch
  desk-startup-apps-script = pkgs.writeShellScriptBin "desk-startup-apps" ''
    #!/bin/bash
    PRIMARY="${if systemSettings.swayPrimaryMonitor != null then systemSettings.swayPrimaryMonitor else ""}"
    
    if [ -z "$PRIMARY" ]; then
      # Not DESK profile, exit
      exit 0
    fi
    
    # Wait a moment for everything to settle
    sleep 2
    
    # Phase 0: Ensure workspaces exist on correct monitors
    # This prevents apps from opening off-screen
    
    # Focus primary monitor first
    ${pkgs.sway}/bin/swaymsg focus output "$PRIMARY"
    
    # Create/focus workspace 1 on primary monitor (ensures it exists)
    ${pkgs.swaysome}/bin/swaysome focus 1
    
    # Create/focus workspace 2 on primary monitor (for Cursor)
    ${pkgs.swaysome}/bin/swaysome focus 2
    
    # Return to workspace 1
    ${pkgs.swaysome}/bin/swaysome focus 1
    
    # Check if DP-2 exists, then ensure workspaces 11 and 12 exist
    # CRITICAL: Use monitor-relative numbers with swaysome
    if ${pkgs.sway}/bin/swaymsg -t get_outputs | ${pkgs.gnugrep}/bin/grep -q "DP-2"; then
        # Focus DP-2
        ${pkgs.sway}/bin/swaymsg focus output DP-2
        # On DP-2, swaysome focus 1 creates workspace 11 (monitor-relative)
        ${pkgs.swaysome}/bin/swaysome focus 1
        # On DP-2, swaysome focus 2 creates workspace 12 (monitor-relative)
        ${pkgs.swaysome}/bin/swaysome focus 2
    else
        # DP-2 not connected, workspaces 11/12 will fallback to DP-1
        # Focus primary and create workspaces there
        ${pkgs.sway}/bin/swaymsg focus output "$PRIMARY"
        ${pkgs.swaysome}/bin/swaysome focus 1  # This creates workspace 11 on DP-1 (fallback)
        ${pkgs.swaysome}/bin/swaysome focus 2  # This creates workspace 12 on DP-1 (fallback)
    fi
    
    # Return to primary monitor, workspace 1
    ${pkgs.sway}/bin/swaymsg focus output "$PRIMARY"
    ${pkgs.swaysome}/bin/swaysome focus 1
    
    # Small delay to ensure workspaces are ready
    sleep 0.5
    
    # Phase 1: Ensure KWallet is running and trigger password prompt
    # kwalletd6 should already be started by daemon-manager, but we verify
    
    # Wait a moment for kwalletd6 to fully start (if it wasn't already)
    sleep 1
    
    # Trigger KWallet to prompt for password by requesting access
    # This will show the password prompt if wallet is locked
    # Using qdbus to request wallet access (triggers prompt if locked)
    # Try multiple qdbus paths, then kwallet-query as fallback
    (command -v qdbus >/dev/null 2>&1 && qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open "kdewallet" 0 "" 2>/dev/null) || \
    (test -f ${pkgs.qt6.qttools}/bin/qdbus && ${pkgs.qt6.qttools}/bin/qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open "kdewallet" 0 "" 2>/dev/null) || \
    (test -f ${pkgs.qt5.qttools}/bin/qdbus && ${pkgs.qt5.qttools}/bin/qdbus org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.open "kdewallet" 0 "" 2>/dev/null) || \
    # Fallback: Use kwallet-query if available
    (${pkgs.kdePackages.kwallet}/bin/kwallet-query kdewallet 2>/dev/null) || true
    
    # Small delay to allow prompt to appear
    sleep 1
    
    # Phase 2: Detect and handle KWallet prompt (BLOCKING - no apps until complete)
    
    KWALLET_PROMPT_FOUND=false
    KWALLET_WINDOW_ID=""
    
    # Wait for KWallet prompt to appear (30 second timeout)
    for i in $(seq 1 30); do
        # Search for KWallet window - check multiple possible names
        KWALLET_WINDOW_ID=$(${pkgs.sway}/bin/swaymsg -t get_tree 2>/dev/null | ${pkgs.jq}/bin/jq -r '
            recurse(.nodes[]?, .floating_nodes[]?) 
            | select(.type=="con" or .type=="floating_con")
            | select(.name != null)
            | select(.name | test("(?i)(kde.?wallet|kwallet|password|unlock)"; "i"))
            | .id' 2>/dev/null | head -1)
        
        if [ -n "$KWALLET_WINDOW_ID" ] && [ "$KWALLET_WINDOW_ID" != "null" ]; then
            KWALLET_PROMPT_FOUND=true
            break
        fi
        sleep 1
    done
    
    if [ "$KWALLET_PROMPT_FOUND" = "true" ]; then
        # CRITICAL: Move KWallet window to main monitor if it's not there
        # Get current output of KWallet window
        CURRENT_OUTPUT=$(${pkgs.sway}/bin/swaymsg -t get_tree 2>/dev/null | ${pkgs.jq}/bin/jq -r "
            recurse(.nodes[]?, .floating_nodes[]?) 
            | select(.id == $KWALLET_WINDOW_ID)
            | .output" 2>/dev/null | head -1)
        
        if [ "$CURRENT_OUTPUT" != "$PRIMARY" ] && [ -n "$CURRENT_OUTPUT" ]; then
            ${pkgs.sway}/bin/swaymsg "[con_id=$KWALLET_WINDOW_ID] move to output $PRIMARY"
        fi
        
        # CRITICAL: Focus the KWallet window so user can type without clicking
        ${pkgs.sway}/bin/swaymsg "[con_id=$KWALLET_WINDOW_ID] focus"
        
        # Wait for window to close (user entered password)
        while [ -n "$(${pkgs.sway}/bin/swaymsg -t get_tree 2>/dev/null | ${pkgs.jq}/bin/jq -r "recurse(.nodes[]?, .floating_nodes[]?) | select(.id == $KWALLET_WINDOW_ID) | .id" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -v null)" ]; do
            sleep 0.5
        done
        
        # Small delay to ensure unlock is fully processed
        sleep 1
    else
        # Prompt not found - check if KWallet is already unlocked
        # Try to verify unlock status via DBus
        # If already unlocked, proceed immediately
        # Small delay in case prompt appears late
        sleep 2
    fi
    
    # Phase 3: Launch ALL apps in parallel (KWallet is now unlocked)
    # Workspaces are guaranteed to exist, KWallet is unlocked
    
    # Ensure secondary monitor workspaces are active before launching apps there
    if ${pkgs.sway}/bin/swaymsg -t get_outputs | ${pkgs.gnugrep}/bin/grep -q "DP-2"; then
        ${pkgs.sway}/bin/swaymsg focus output DP-2
        ${pkgs.swaysome}/bin/swaysome focus 1 # Creates/activates workspace 11
        ${pkgs.swaysome}/bin/swaysome focus 2 # Creates/activates workspace 12
    fi
    
    # Launch all apps in parallel
    # Vivaldi on primary monitor, workspace 1
    ${pkgs.sway}/bin/swaymsg focus output "$PRIMARY"
    ${pkgs.swaysome}/bin/swaysome focus 1
    ${pkgs.flatpak}/bin/flatpak run com.vivaldi.Vivaldi >/dev/null 2>&1 &
    
    # Cursor on primary monitor, workspace 2
    ${pkgs.sway}/bin/swaymsg focus output "$PRIMARY"
    ${pkgs.swaysome}/bin/swaysome focus 2
    cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland --ozone-platform-hint=auto --unity-launch >/dev/null 2>&1 &
    
    # Obsidian on secondary monitor, workspace 11
    obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations >/dev/null 2>&1 &
    
    # Chromium on secondary monitor, workspace 12
    chromium >/dev/null 2>&1 &
    
    # Return focus to primary monitor, workspace 1 (where Vivaldi is)
    ${pkgs.sway}/bin/swaymsg focus output "$PRIMARY"
    ${pkgs.swaysome}/bin/swaysome focus 1
  '';
  
  # Daemon definitions - shared by all generated scripts (DRY principle)
  # WARNING: Sway and Hyprland both use programs.waybar which writes to
  # ~/.config/waybar/config. They are mutually exclusive in the same profile.
  # If both WMs are enabled, Home Manager will have a file conflict.
  daemons = [
    {
      name = "waybar";
      # Official NixOS Waybar setup with SwayFX:
      # - programs.waybar.enable = true (configured in waybar.nix)
      # - systemd.enable = false (managed by daemon-manager, not systemd)
      # - Official way: exec waybar in Sway config, but we use daemon-manager for better control
      # - Explicit config path ensures waybar uses the correct config file generated by programs.waybar.settings
      # Reference: https://wiki.nixos.org/wiki/Waybar
      # TEMPORARY: Added -l info for debugging workspace visibility issue
      command = "${pkgs.waybar}/bin/waybar -l info -c ${config.xdg.configHome}/waybar/config";
      # CRITICAL: Pattern matching for NixOS-wrapped binaries
      # NixOS wraps binaries: waybar -> .waybar-wrapped (process name changes)
      # Using pgrep -f matches full command line with anchored pattern (^) to match binary path regardless of flags
      # This matches the main waybar process with any flags (-c, -l info, etc.)
      # The ^ anchor ensures we match the start of the command line, preventing substring matches
      pattern = "^${pkgs.waybar}/bin/waybar";  # Anchored pattern matches binary path regardless of flags
      match_type = "full";  # Essential for NixOS wrapper (.waybar-wrapped) - matches full command line
      # Official reload method: SIGUSR2 for waybar (hot reload CSS/config)
      # Reference: https://github.com/Alexays/Waybar/wiki/Configuration
      # Using anchored pkill pattern to match any waybar command with this store path
      reload = "${pkgs.procps}/bin/pkill -USR2 -f '^${pkgs.waybar}/bin/waybar'";  # Anchored pattern for reliable reload
      requires_sway = true;  # Wait for SwayFX IPC to be ready before starting
    }
    {
      name = "swaync";
      command = "${pkgs.swaynotificationcenter}/bin/swaync";
      pattern = "swaync";
      match_type = "full";  # Fixes "An instance is already running" (NixOS wrapper)
      reload = "${pkgs.swaynotificationcenter}/bin/swaync-client -R";
      requires_sway = true;
    }
    {
      name = "nm-applet";
      command = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      pattern = "nm-applet";
      match_type = "full";  # NixOS wrapper
      reload = "";
      requires_sway = false;
      requires_tray = true;  # Wait for waybar's tray (StatusNotifierWatcher) to be ready
    }
    {
      name = "blueman-applet";
      command = "${pkgs.blueman}/bin/blueman-applet";
      pattern = "blueman-applet";
      match_type = "full";  # NixOS wrapper
      reload = "";
      requires_sway = false;
      requires_tray = true;  # Wait for waybar's tray (StatusNotifierWatcher) to be ready
    }
    {
      name = "cliphist";
      command = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
      pattern = "wl-paste.*cliphist";  # Regex pattern for full command match
      match_type = "full";  # Use pgrep -f for full command match (needed for complex commands)
      reload = "";
      requires_sway = true;
    }
    {
      name = "kwalletd6";
      command = "${pkgs.kdePackages.kwallet}/bin/kwalletd6";
      pattern = "kwalletd6";
      match_type = "full";  # KDE daemons are always wrapped on NixOS
      reload = "";
      requires_sway = false;
    }
  ] ++ lib.optionals (
    # Only include libinput-gestures on laptop systems (has touchpad)
    # Desktop systems (DESK, AGADESK, VMDESK) don't have touchpads
    lib.hasInfix "laptop" (lib.toLower systemSettings.hostname) ||
    lib.hasInfix "yoga" (lib.toLower systemSettings.hostname)
  ) [
    {
      name = "libinput-gestures";
      command = "${pkgs.libinput-gestures}/bin/libinput-gestures";
      pattern = "libinput-gestures";
      match_type = "full";  # Python script/wrapper - full match required
      reload = "";
      requires_sway = true;  # Needs SwayFX IPC to send workspace commands
    }
  ] ++ lib.optional (systemSettings.sunshineEnable == true) {
    name = "sunshine";
    command = "${pkgs.sunshine}/bin/sunshine";
    pattern = "sunshine";
    match_type = "full";  # NixOS wrapper - full match required
    reload = "";
    requires_sway = false;
    requires_tray = true;  # Wait for waybar's tray (StatusNotifierWatcher) to be ready
  } ++ lib.optional (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) {
    name = "swaybg";
    command = "${pkgs.swaybg}/bin/swaybg -i ${config.stylix.image} -m fill";
    pattern = "swaybg";
    match_type = "full";  # NixOS wrapper - full match required
    reload = "";
    requires_sway = true;
  };
  
  # Generate daemon-manager script
  daemon-manager = pkgs.writeShellScriptBin "daemon-manager" ''
    #!/bin/sh
    # Unified daemon manager for SwayFX
    # Usage: daemon-manager [PATTERN] [MATCH_TYPE] [COMMAND] [RELOAD_CMD] [REQUIRES_SWAY] [REQUIRES_TRAY]
    
    PATTERN="$1"
    MATCH_TYPE="$2"
    COMMAND="$3"
    RELOAD_CMD="$4"
    REQUIRES_SWAY="$5"
    REQUIRES_TRAY="$6"
    
    # Determine pgrep flags based on match_type
    # Note: We no longer use pkill - safe_kill uses pgrep + kill instead
    if [ "$MATCH_TYPE" = "exact" ]; then
      PGREP_FLAG="-x"
    else
      PGREP_FLAG="-f"
    fi
    
    # Logging function using systemd-cat
    # systemd-cat is a standard system utility available in PATH
    log() {
      echo "$1" | systemd-cat -t sway-daemon-mgr -p "$2"
    }
    
    # Safe kill function - prevents self-termination by excluding script's own PID and parent PID
    # CRITICAL: pkill -f matches command line arguments, which can include the pattern we're searching for
    # This causes the script to kill itself. This function filters out $$ and $PPID before killing.
    safe_kill() {
      local KILL_PATTERN="$1"
      local KILL_PGREP_FLAG="$2"
      local SELF_PID=$$
      local PARENT_PID=$PPID
      local KILLED_COUNT=0
      
      # Get all matching PIDs
      MATCHING_PIDS=$(${pkgs.procps}/bin/pgrep $KILL_PGREP_FLAG "$KILL_PATTERN" 2>/dev/null || echo "")
      
      if [ -z "$MATCHING_PIDS" ]; then
        return 0
      fi
      
      # Filter and kill (exclude self and parent)
      for PID in $MATCHING_PIDS; do
        if [ "$PID" != "$SELF_PID" ] && [ "$PID" != "$PARENT_PID" ]; then
          kill "$PID" 2>/dev/null && KILLED_COUNT=$((KILLED_COUNT + 1)) || true
        fi
      done
      return 0
    }
    
    # Check if process is running and count instances
    RUNNING_PIDS=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null || echo "")
    RUNNING_COUNT=$(echo "$RUNNING_PIDS" | grep -v "^$" | wc -l)
    
    # CRITICAL: For waybar, also check for old patterns from previous rebuilds
    # Old waybar processes might be running with old store paths or simplified patterns
    # We need to kill these to prevent conflicts
    if echo "$PATTERN" | grep -q "waybar -c"; then
      # Check for old patterns: /bin/waybar, waybar -c (without store path), or old store paths
      # Also check for any waybar process that doesn't match the current pattern
      OLD_PATTERNS="/bin/waybar waybar -c"
      for OLD_PAT in $OLD_PATTERNS; do
        OLD_PIDS=$(${pkgs.procps}/bin/pgrep -f "$OLD_PAT" 2>/dev/null | grep -v "^$" || echo "")
        if [ -n "$OLD_PIDS" ]; then
          # Check if these PIDs are different from the current pattern's PIDs
          for OLD_PID in $OLD_PIDS; do
            if ! echo "$RUNNING_PIDS" | grep -q "^''${OLD_PID}$"; then
              log "WARNING: Found old waybar process (PID: $OLD_PID, pattern: $OLD_PAT), killing it" "warning"
              # Use kill -9 for stubborn processes
              kill -9 "$OLD_PID" 2>/dev/null || true
            fi
          done
        fi
      done
      # Also kill any waybar process that doesn't match the current store path pattern
      # This catches processes from previous rebuilds with different store paths
      ALL_WAYBAR_PIDS=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | grep -v "^$" || echo "")
      CURRENT_STORE_PATH=$(echo "$PATTERN" | sed 's|/bin/waybar.*||')
      for WB_PID in $ALL_WAYBAR_PIDS; do
        # Check if this PID's command line contains the current store path
        WB_CMD=$(ps -p "$WB_PID" -o cmd= 2>/dev/null || echo "")
        if [ -n "$WB_CMD" ] && ! echo "$WB_CMD" | grep -q "$CURRENT_STORE_PATH"; then
          if ! echo "$RUNNING_PIDS" | grep -q "^''${WB_PID}$"; then
            log "WARNING: Found old waybar process (PID: $WB_PID, old store path), killing it" "warning"
            kill -9 "$WB_PID" 2>/dev/null || true
          fi
        fi
      done
      
      # #region agent log
      echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:check-instances\",\"message\":\"Checking waybar instances\",\"data\":{\"pattern\":\"$PATTERN\",\"runningCount\":\"$RUNNING_COUNT\",\"pids\":\"$RUNNING_PIDS\",\"hypothesisId\":\"D\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
      # #endregion
    fi
    
    if [ -n "$RUNNING_PIDS" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
      # Process(es) running - check for duplicates
      if [ "$RUNNING_COUNT" -gt 1 ]; then
        # Multiple instances detected - kill all and restart with exponential backoff
        log "WARNING: Multiple instances detected ($RUNNING_COUNT), killing all: $PATTERN" "warning"
        safe_kill "$PATTERN" "$PGREP_FLAG"
        
        # Exponential backoff verification: wait progressively longer to ensure processes are dead
        # This prevents race conditions where processes are still terminating
        REMAINING=$RUNNING_COUNT
        for wait_time in 0.5 1 2; do
          sleep $wait_time
          REMAINING=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null | wc -l)
          if [ "$REMAINING" -eq 0 ]; then
            break
          fi
          # If processes still exist, try killing again (they might have been in a bad state)
          if [ "$REMAINING" -gt 0 ]; then
            log "WARNING: Still $REMAINING processes remaining, attempting kill again: $PATTERN" "warning"
            safe_kill "$PATTERN" "$PGREP_FLAG"
          fi
        done
        
        # Final verification: if processes still exist after all attempts, log warning but proceed
        if [ "$REMAINING" -gt 0 ]; then
          log "WARNING: $REMAINING processes still remaining after kill attempts, proceeding anyway: $PATTERN" "warning"
        else
          log "All duplicate processes successfully terminated: $PATTERN" "info"
        fi
        
        log "Falling through to start fresh instance after killing duplicates: $PATTERN" "info"
        # CRITICAL: Force fall-through by clearing RUNNING_COUNT so we don't hit the single-instance check below
        RUNNING_COUNT=0
        RUNNING_PIDS=""
        # Fall through to start fresh instance
      elif [ -n "$RELOAD_CMD" ]; then
        # Single instance running and supports reload - send reload signal
        # Using anchored pkill patterns (^) prevents self-matching and is atomic (no TOCTOU race)
        # All reload commands are safe to use directly with eval
        log "Sending reload signal to daemon: $PATTERN" "info"
        eval "$RELOAD_CMD"
        log "Reload signal sent to daemon: $PATTERN" "info"
        exit 0
      else
        # Single instance running but no reload support - leave it running
        log "Daemon already running: $PATTERN (PID: $RUNNING_PIDS)" "info"
        exit 0
      fi
    fi
    
    # Process not running - start it
    if [ "$REQUIRES_SWAY" = "true" ]; then
      # Wait for SwayFX IPC to be ready (max 15 seconds with exponential backoff)
      # CRITICAL: For waybar, we need to ensure SwayFX IPC is fully functional, not just responding
      SWAY_READY=false
      for delay in 0.5 1 1.5 2 2.5 3; do
        # Check if swaymsg works AND can actually query outputs (proves IPC is functional)
        if ${pkgs.swayfx}/bin/swaymsg -t get_outputs > /dev/null 2>&1 && \
           ${pkgs.swayfx}/bin/swaymsg -t get_workspaces > /dev/null 2>&1; then
          SWAY_READY=true
          log "SwayFX IPC is ready (waited ~''${delay}s): $PATTERN" "info"
          break
        fi
        sleep $delay
      done
      if [ "$SWAY_READY" = "false" ]; then
        log "WARNING: SwayFX not ready after 15 seconds, starting daemon anyway: $PATTERN" "warning"
        # #region agent log
        if [ "$PATTERN" = "waybar -c" ]; then
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:sway-not-ready\",\"message\":\"SwayFX not ready for waybar\",\"data\":{\"pattern\":\"$PATTERN\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        fi
        # #endregion
      fi
    fi
    
    if [ "$REQUIRES_TRAY" = "true" ]; then
      # Wait for StatusNotifierWatcher to be ready (exponential backoff: 0.5s, 1s, 2s, 4s, 8s = 15.5s total)
      # NOTE: On Sway/Hyprland, Waybar itself acts as the StatusNotifierWatcher when its tray module is enabled
      # This ensures waybar's tray module has registered before applets try to connect
      TRAY_READY=false
      TOTAL_WAIT=0
      CHECK_COUNT=0
      for delay in 0.5 1 2 4 8; do
        # Check if org.freedesktop.StatusNotifierWatcher is available on DBus
        # This checks if Waybar (or another watcher) has registered the service
        if ${pkgs.dbus}/bin/dbus-send --session --print-reply \
          --dest=org.freedesktop.DBus \
          /org/freedesktop/DBus \
          org.freedesktop.DBus.GetNameOwner \
          string:org.freedesktop.StatusNotifierWatcher > /dev/null 2>&1; then
          TRAY_READY=true
          log "StatusNotifierWatcher is ready (check #$CHECK_COUNT, waited ~''${TOTAL_WAIT} seconds)" "info"
          break
        fi
        CHECK_COUNT=$((CHECK_COUNT + 1))
        # Sleep before next check (exponential backoff)
        sleep $delay
        # Approximate total wait (using integer arithmetic)
        TOTAL_WAIT=$((TOTAL_WAIT + 1))  # Approximate, close enough for logging
      done
      if [ "$TRAY_READY" = "false" ]; then
        log "WARNING: StatusNotifierWatcher not ready after ~15 seconds, starting daemon anyway: $PATTERN" "warning"
        log "NOTE: Tray icon may not appear until waybar's tray module initializes" "info"
      fi
    fi
    
    # Kill any stale processes (safety check even though we checked above)
    # Use safe_kill to prevent self-termination
    safe_kill "$PATTERN" "$PGREP_FLAG"
    sleep 0.5
    
    # Final verification: ensure no processes are running before starting
    FINAL_CHECK=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null | wc -l)
    if [ "$FINAL_CHECK" -gt 0 ]; then
      log "WARNING: $FINAL_CHECK processes still running before start, killing again: $PATTERN" "warning"
      safe_kill "$PATTERN" "$PGREP_FLAG"
      sleep 1
    fi
    
    # Start daemon with systemd logging
    log "Starting daemon: $PATTERN (command: $COMMAND)" "info"
    # #region agent log
    echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:start\",\"message\":\"Starting daemon\",\"data\":{\"pattern\":\"$PATTERN\",\"command\":\"$COMMAND\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
    # #endregion
    
    # Official Waybar debugging: Check environment variables and Wayland socket
    # Reference: https://github.com/Alexays/Waybar/wiki/Troubleshooting
    if echo "$PATTERN" | grep -q "waybar"; then
      # Check Wayland display (official waybar requirement)
      if [ -z "$WAYLAND_DISPLAY" ]; then
        log "WARNING: WAYLAND_DISPLAY not set for waybar (may cause connection issues)" "warning"
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-env-check\",\"message\":\"WAYLAND_DISPLAY not set\",\"data\":{\"pattern\":\"$PATTERN\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      else
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-env-check\",\"message\":\"WAYLAND_DISPLAY is set\",\"data\":{\"pattern\":\"$PATTERN\",\"waylandDisplay\":\"$WAYLAND_DISPLAY\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
      # Check if SwayFX socket exists (official waybar requirement for sway/workspaces module)
      # SwayFX IPC socket format: $XDG_RUNTIME_DIR/sway-ipc.<uid>.<pid>.sock
      # Reference: https://github.com/Alexays/Waybar/wiki/Module:-sway-workspaces
      if [ -n "$XDG_RUNTIME_DIR" ]; then
        SWAY_PID=$(pgrep -x swayfx | head -1)
        if [ -n "$SWAY_PID" ]; then
          SWAY_SOCKET="''${XDG_RUNTIME_DIR}/sway-ipc.$(id -u).''${SWAY_PID}.sock"
          if [ -S "$SWAY_SOCKET" ]; then
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-socket-check\",\"message\":\"SwayFX socket found\",\"data\":{\"pattern\":\"$PATTERN\",\"socket\":\"$SWAY_SOCKET\",\"swayPid\":\"$SWAY_PID\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          else
            log "WARNING: SwayFX IPC socket not found: $SWAY_SOCKET (waybar sway/workspaces module may fail)" "warning"
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-socket-check\",\"message\":\"SwayFX socket not found\",\"data\":{\"pattern\":\"$PATTERN\",\"socket\":\"$SWAY_SOCKET\",\"swayPid\":\"$SWAY_PID\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          fi
        else
          log "WARNING: SwayFX process not found (waybar sway/workspaces module will fail)" "warning"
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-sway-check\",\"message\":\"SwayFX process not found\",\"data\":{\"pattern\":\"$PATTERN\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
        fi
      fi
    fi
    # CRITICAL: For pipe commands, use bash -c to ensure proper pipe handling
    # Commands containing pipes need bash for proper pipe execution
    # Use grep -F for fixed string matching (literal pipe character)
    HAS_PIPE=false
    if echo "$COMMAND" | grep -Fq "|"; then
      HAS_PIPE=true
      log "Detected pipe in command, using bash: $PATTERN" "info"
    else
      log "No pipe detected, using sh: $PATTERN" "info"
    fi
    
    # Start daemon with proper shell and capture both stdout and stderr to temp files
    # Then tail those files to systemd for real-time monitoring
    # Sanitize pattern for use in filenames (replace special chars with underscores)
    PATTERN_SANITIZED=$(echo "$PATTERN" | tr -d '.*+?^$[](){}|' | tr ' ' '_' | tr '/' '_')
    STDOUT_LOG="/tmp/daemon-''${PATTERN_SANITIZED}-stdout.log"
    STDERR_LOG="/tmp/daemon-''${PATTERN_SANITIZED}-stderr.log"
    rm -f "$STDOUT_LOG" "$STDERR_LOG"
    if [ "$HAS_PIPE" = "true" ]; then
      # Pipe command - use bash
      nohup bash -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
    else
      # Simple command - use sh
      nohup sh -c "$COMMAND" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
    fi
    DAEMON_PID=$!
    log "Daemon start command executed, PID: $DAEMON_PID (pattern: $PATTERN, has_pipe: $HAS_PIPE)" "info"
    
    # CRITICAL: Check if process is still alive after a brief moment to detect immediate crashes
    sleep 0.3
    if ! kill -0 $DAEMON_PID 2>/dev/null; then
      # Process died - check error logs
      if [ -f "$STDERR_LOG" ]; then
        ERROR_OUTPUT=$(cat "$STDERR_LOG" 2>/dev/null | head -50 | tr '\n' ' ' || echo "")
        log "ERROR: Daemon process died immediately (PID: $DAEMON_PID, pattern: $PATTERN). Error: $ERROR_OUTPUT" "err"
        
        # For waybar, check for CSS errors specifically
        if echo "$PATTERN" | grep -q "waybar -c"; then
          CSS_ERRORS=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(css|style|parse|syntax|error|invalid|unknown|property|selector)" || echo "")
          if [ -n "$CSS_ERRORS" ]; then
            CSS_ERROR_SUMMARY=$(echo "$CSS_ERRORS" | head -20 | tr '\n' '|' | sed 's/|$//')
            log "CRITICAL: Waybar CSS errors detected: $CSS_ERROR_SUMMARY" "err"
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-immediate-css-crash\",\"message\":\"Waybar crashed immediately with CSS errors\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"cssErrors\":\"$CSS_ERROR_SUMMARY\",\"fullError\":\"$ERROR_OUTPUT\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          else
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:immediate-crash\",\"message\":\"Daemon crashed immediately\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"error\":\"$ERROR_OUTPUT\",\"hasCssErrors\":\"false\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          fi
        else
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:immediate-crash\",\"message\":\"Daemon crashed immediately\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"error\":\"$ERROR_OUTPUT\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
        fi
      else
        log "ERROR: Daemon process died immediately (PID: $DAEMON_PID, pattern: $PATTERN). No error log available." "err"
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:immediate-crash\",\"message\":\"Daemon crashed immediately (no logs)\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
    else
      # #region agent log
      echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:process-alive\",\"message\":\"Process still alive after 0.3s\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
      # #endregion
    fi
    
    # Also pipe logs to systemd for real-time monitoring (background processes)
    # Only start tail processes if log files exist and are non-empty
    # Track tail PIDs for cleanup to prevent orphaned processes
    # CRITICAL: Start tail processes in background without subshell to capture correct PID
    TAIL_STDOUT_PID=""
    TAIL_STDERR_PID=""
    
    if [ -f "$STDOUT_LOG" ] && [ -s "$STDOUT_LOG" ]; then
      tail -f "$STDOUT_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN_SANITIZED}" -p info &
      TAIL_STDOUT_PID=$!
    fi
    if [ -f "$STDERR_LOG" ] && [ -s "$STDERR_LOG" ]; then
      tail -f "$STDERR_LOG" 2>/dev/null | systemd-cat -t "sway-daemon-''${PATTERN_SANITIZED}" -p err &
      TAIL_STDERR_PID=$!
    fi
    
    # Cleanup function to kill orphaned tail processes
    # Also kill any remaining tail processes matching the pattern (safety net)
    cleanup_tails() {
      [ -n "$TAIL_STDOUT_PID" ] && kill "$TAIL_STDOUT_PID" 2>/dev/null || true
      [ -n "$TAIL_STDERR_PID" ] && kill "$TAIL_STDERR_PID" 2>/dev/null || true
      # Safety net: kill any orphaned tail processes for this daemon's logs
      ${pkgs.procps}/bin/pkill -f "tail -f.*daemon-''${PATTERN_SANITIZED}" 2>/dev/null || true
    }
    trap cleanup_tails EXIT
    
    # Verify it started with progressive wait (some daemons take longer to initialize)
    # Use exponential backoff: check quickly first, then wait longer
    DAEMON_STARTED=false
    for check_delay in 0.5 1 2; do
      sleep $check_delay
      VERIFY_RESULT=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" 2>/dev/null || echo "")
      if [ -n "$VERIFY_RESULT" ]; then
        ACTUAL_PID=$(echo "$VERIFY_RESULT" | head -1)
        log "Daemon started successfully: $PATTERN (started PID: $DAEMON_PID, actual PID: $ACTUAL_PID, verified after ''${check_delay}s)" "info"
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:verification-success\",\"message\":\"Daemon verified running\",\"data\":{\"pattern\":\"$PATTERN\",\"startedPid\":\"$DAEMON_PID\",\"actualPid\":\"$ACTUAL_PID\",\"checkDelay\":\"$check_delay\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
        DAEMON_STARTED=true
        break
      else
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:verification-check\",\"message\":\"Daemon not found in verification\",\"data\":{\"pattern\":\"$PATTERN\",\"startedPid\":\"$DAEMON_PID\",\"checkDelay\":\"$check_delay\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
    done
    
    # CRITICAL: For waybar, add post-verification health check
    # Waybar often crashes 1-2 seconds after launch due to DBus/Portal timeouts or SwayFX IPC issues
    # We must wait for this window to catch crashes during Wayland initialization
    if [ "$DAEMON_STARTED" = "true" ] && echo "$PATTERN" | grep -q "waybar -c"; then
      # #region agent log
      echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-pre-check\",\"message\":\"Starting waybar post-verification check\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
      # #endregion
      
      # Check for CSS errors in stderr before the health check
      if [ -f "$STDERR_LOG" ]; then
        CSS_ERRORS=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(css|style|parse|syntax|error|invalid|unknown)" || echo "")
        if [ -n "$CSS_ERRORS" ]; then
          CSS_ERROR_SUMMARY=$(echo "$CSS_ERRORS" | head -10 | tr '\n' '|' | sed 's/|$//')
          log "WARNING: Potential CSS errors detected in Waybar stderr: $CSS_ERROR_SUMMARY" "warning"
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-css-errors\",\"message\":\"CSS errors detected in stderr\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"cssErrors\":\"$CSS_ERROR_SUMMARY\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
        fi
      fi
      
      # CRITICAL: Extended post-verification check for waybar
      # Waybar can crash 3-5 seconds after launch due to SwayFX IPC timeouts or module initialization
      # Check at 2s, 4s, and 6s (incremental sleeps) to catch delayed crashes
      WAYBAR_STILL_RUNNING=true
      TOTAL_WAIT=0
      for sleep_duration in 2 2 2; do
        sleep $sleep_duration
        TOTAL_WAIT=$((TOTAL_WAIT + sleep_duration))
        if ! ${pkgs.procps}/bin/pgrep $PGREP_FLAG "$PATTERN" >/dev/null 2>&1; then
          WAYBAR_STILL_RUNNING=false
          log "ERROR: Waybar crashed after initial verification (at ''${TOTAL_WAIT}s check, during Wayland/module init)" "err"
          
          # Capture full error details for debugging
          FULL_STDERR=""
          FULL_STDOUT=""
          EXIT_CODE="unknown"
          PROCESS_TREE=""
          if [ -f "$STDERR_LOG" ]; then
            FULL_STDERR=$(cat "$STDERR_LOG" 2>/dev/null | head -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          fi
          if [ -f "$STDOUT_LOG" ]; then
            FULL_STDOUT=$(cat "$STDOUT_LOG" 2>/dev/null | head -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          fi
          # Try to get exit code from wait (if process was waited on)
          # Check for multiple instances
          ALL_WAYBAR_PROCS=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
          PROCESS_TREE=$(ps aux | grep -E "waybar|daemon-manager|daemon-health-monitor" | grep -v grep | head -10 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-crash-timing\",\"message\":\"Waybar crashed at ''${TOTAL_WAIT}s check\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"checkTime\":\"''${TOTAL_WAIT}s\",\"allWaybarProcs\":\"$ALL_WAYBAR_PROCS\",\"stderrBase64\":\"$FULL_STDERR\",\"stdoutBase64\":\"$FULL_STDOUT\",\"processTree\":\"$PROCESS_TREE\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
          break
        fi
      done
      
      if [ "$WAYBAR_STILL_RUNNING" = "false" ]; then
        if [ -f "$STDERR_LOG" ]; then
          ERROR_CONTENT=$(cat "$STDERR_LOG" 2>/dev/null | tail -50 | tr '\n' ' ' || echo "")
          log "Waybar crash error: $ERROR_CONTENT" "err"
          
          # Extract CSS-specific errors
          CSS_CRASH_ERRORS=$(cat "$STDERR_LOG" 2>/dev/null | grep -iE "(css|style|parse|syntax|error|invalid|unknown|property|selector)" || echo "")
          if [ -n "$CSS_CRASH_ERRORS" ]; then
            CSS_CRASH_SUMMARY=$(echo "$CSS_CRASH_ERRORS" | head -20 | tr '\n' '|' | sed 's/|$//')
            log "CRITICAL: CSS errors found in crash log: $CSS_CRASH_SUMMARY" "err"
          fi
          
          # Capture full error details
          FULL_STDERR_CRASH=$(cat "$STDERR_LOG" 2>/dev/null | head -200 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          FULL_STDOUT_CRASH=$(cat "$STDOUT_LOG" 2>/dev/null | head -200 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
          ALL_WAYBAR_PROCS_CRASH=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
          HEALTH_MONITOR_RUNNING=$(${pkgs.procps}/bin/pgrep -f "daemon-health-monitor" >/dev/null 2>&1 && echo "true" || echo "false")
          
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-crash\",\"message\":\"Waybar crashed after post-verification\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"error\":\"$ERROR_CONTENT\",\"hasCssErrors\":\"$([ -n \"$CSS_CRASH_ERRORS\" ] && echo \"true\" || echo \"false\")\",\"cssErrors\":\"$CSS_CRASH_SUMMARY\",\"fullStderrBase64\":\"$FULL_STDERR_CRASH\",\"fullStdoutBase64\":\"$FULL_STDOUT_CRASH\",\"allWaybarProcs\":\"$ALL_WAYBAR_PROCS_CRASH\",\"healthMonitorRunning\":\"$HEALTH_MONITOR_RUNNING\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
        else
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-crash\",\"message\":\"Waybar crashed after post-verification (no logs)\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
        fi
        DAEMON_STARTED=false
      else
        log "Waybar health check passed (post-verification, survived 6s check)" "info"
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"daemon-manager:waybar-healthy\",\"message\":\"Waybar health check passed (survived 6s)\",\"data\":{\"pattern\":\"$PATTERN\",\"pid\":\"$DAEMON_PID\",\"hypothesisId\":\"C\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
    fi
    
    if [ "$DAEMON_STARTED" = "false" ]; then
      # Additional check: see if process started but verification failed
      CHECK_CMD=$(ps -p $DAEMON_PID -o comm= 2>/dev/null || echo "not_found")
      log "ERROR: Failed to start daemon: $PATTERN (started PID: $DAEMON_PID, process: $CHECK_CMD)" "err"
      exit 1
    fi
  '';
  
  # Generate startup script (iterates daemon list)
  start-sway-daemons = pkgs.writeShellScriptBin "start-sway-daemons" ''
    #!/bin/sh
    # Auto-generated script - starts all SwayFX daemons
    # Do not edit manually - generated from daemon list in default.nix
    
    # File locking to prevent concurrent execution (e.g., rapid reload spam)
    # Uses XDG runtime directory which is automatically cleaned on logout/reboot
    # CRITICAL: Use simple atomic lock - no retry logic to prevent race conditions
    LOCK_FILE="/run/user/$(id -u)/sway-startup.lock"
    (
      # Original working design: immediate exit if lock is held (prevents race conditions)
      flock -n 9 || { 
        echo "Another startup process is running, exiting" | systemd-cat -t sway-daemon-mgr -p info
        exit 0 
      }
      
      # Official Waybar Config Validation (non-blocking)
      # Reference: https://github.com/Alexays/Waybar/wiki/Configuration
      # Waybar config files are auto-generated by Home Manager programs.waybar module
      # Location: ~/.config/waybar/config (JSON/JSONC) and ~/.config/waybar/style.css
      WAYBAR_CONFIG="${config.xdg.configHome}/waybar/config"
      WAYBAR_CSS="${config.xdg.configHome}/waybar/style.css"
      if [ -f "$WAYBAR_CONFIG" ]; then
        # Official validation: Waybar config should be valid JSON/JSONC
        # Try to validate JSON structure (if jq is available) - non-blocking
        if command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
          if ! ${pkgs.jq}/bin/jq empty "$WAYBAR_CONFIG" 2>/dev/null; then
            echo "WARNING: Waybar config JSON validation failed (non-blocking)" | systemd-cat -t sway-daemon-mgr -p warning
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"start-sway-daemons:config-validation\",\"message\":\"Waybar config JSON validation failed\",\"data\":{\"configFile\":\"$WAYBAR_CONFIG\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          else
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"start-sway-daemons:config-valid\",\"message\":\"Waybar config JSON validation passed\",\"data\":{\"configFile\":\"$WAYBAR_CONFIG\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          fi
        fi
      else
        echo "WARNING: Waybar config file missing (non-blocking) - Home Manager should generate this" | systemd-cat -t sway-daemon-mgr -p warning
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"start-sway-daemons:config-missing\",\"message\":\"Waybar config file missing\",\"data\":{\"configFile\":\"$WAYBAR_CONFIG\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
      # Check CSS file exists (official waybar requirement)
      if [ ! -f "$WAYBAR_CSS" ]; then
        echo "WARNING: Waybar CSS file missing (non-blocking) - Home Manager should generate this" | systemd-cat -t sway-daemon-mgr -p warning
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"start-sway-daemons:css-missing\",\"message\":\"Waybar CSS file missing\",\"data\":{\"cssFile\":\"$WAYBAR_CSS\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      else
        # #region agent log
        echo "{\"timestamp\":$(date +%s000),\"location\":\"start-sway-daemons:css-exists\",\"message\":\"Waybar CSS file exists\",\"data\":{\"cssFile\":\"$WAYBAR_CSS\",\"hypothesisId\":\"A\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
        # #endregion
      fi
      
      # Start waybar first (synchronously) to avoid race conditions
      # Waybar is critical and multiple parallel instances cause conflicts
      ${lib.concatMapStringsSep "\n" (daemon: ''
        if [ "${daemon.name}" = "waybar" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"}
        fi
      '') daemons}
      
      # Start all other daemons in parallel
      ${lib.concatMapStringsSep "\n" (daemon: ''
        if [ "${daemon.name}" != "waybar" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"} &
        fi
      '') daemons}
      wait
    ) 9>"$LOCK_FILE"
  '';
  
  # Generate sanity check script (uses same daemon list)
  daemon-sanity-check = pkgs.writeShellScriptBin "daemon-sanity-check" ''
    #!/bin/sh
    # Auto-generated script - checks status of all SwayFX daemons
    # Do not edit manually - generated from daemon list in default.nix
    
    FIX_MODE=false
    if [ "$1" = "--fix" ]; then
      FIX_MODE=true
    fi
    
    ALL_RUNNING=true
    ${lib.concatMapStringsSep "\n" (daemon: ''
      MATCH_TYPE=${lib.strings.escapeShellArg daemon.match_type}
      if [ "$MATCH_TYPE" = "exact" ]; then
        PGREP_FLAG="-x"
      else
        PGREP_FLAG="-f"
      fi
      
      if ${pkgs.procps}/bin/pgrep $PGREP_FLAG ${lib.strings.escapeShellArg daemon.pattern} > /dev/null 2>&1; then
        echo "✓ ${daemon.name} is running" | systemd-cat -t sway-daemon-check -p info
      else
        echo "✗ ${daemon.name} is NOT running" | systemd-cat -t sway-daemon-check -p warning
        ALL_RUNNING=false
        if [ "$FIX_MODE" = "true" ]; then
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"}
        fi
      fi
    '') daemons}
    
    if [ "$ALL_RUNNING" = "true" ]; then
      exit 0
    else
      exit 1
    fi
  '';
  
  # Generate daemon health monitor script (periodically checks and restarts crashed daemons)
  daemon-health-monitor = pkgs.writeShellScriptBin "daemon-health-monitor" ''
    #!/bin/sh
    # Daemon health monitor - periodically checks daemon health and restarts crashed daemons
    # Runs continuously in background (not managed by daemon-manager to avoid circular dependency)
    
    # Logging function using systemd-cat
    log() {
      echo "$1" | systemd-cat -t sway-daemon-monitor -p "$2"
    }
    
    # Track restart attempts per daemon to implement exponential backoff
    RESTART_ATTEMPTS=""
    
    # Get restart count for a daemon
    get_restart_count() {
      local DAEMON_NAME="$1"
      echo "$RESTART_ATTEMPTS" | grep "^$DAEMON_NAME:" | cut -d: -f2 || echo "0"
    }
    
    # Increment restart count for a daemon
    increment_restart_count() {
      local DAEMON_NAME="$1"
      local CURRENT=$(get_restart_count "$DAEMON_NAME")
      local NEW=$((CURRENT + 1))
      RESTART_ATTEMPTS=$(echo "$RESTART_ATTEMPTS" | grep -v "^$DAEMON_NAME:" || true)
      RESTART_ATTEMPTS="$RESTART_ATTEMPTS"$'\n'"$DAEMON_NAME:$NEW"
    }
    
    # Reset restart count for a daemon (when it's healthy)
    reset_restart_count() {
      local DAEMON_NAME="$1"
      RESTART_ATTEMPTS=$(echo "$RESTART_ATTEMPTS" | grep -v "^$DAEMON_NAME:" || true)
    }
    
    log "Daemon health monitor started" "info"
    
    # CRITICAL: Grace period after startup to avoid false negatives during SwayFX initialization
    # Wait 60 seconds before starting monitoring to allow SwayFX and daemons to fully initialize
    # This prevents the health monitor from incorrectly restarting daemons during the startup phase
    log "Health monitor: Waiting 60 seconds grace period for system initialization" "info"
    sleep 60
    
    # CRITICAL: Initialize failure counters BEFORE while loop to persist across iterations
    # If initialized inside the loop, they reset every 30 seconds and strike system never triggers
    WAYBAR_FAILURE_COUNT=0
    
    # Main monitoring loop (check every 30 seconds)
    while true; do
      sleep 30
      
      ${lib.concatMapStringsSep "\n" (daemon: ''
        MATCH_TYPE=${lib.strings.escapeShellArg daemon.match_type}
        if [ "$MATCH_TYPE" = "exact" ]; then
          PGREP_FLAG="-x"
        else
          PGREP_FLAG="-f"
        fi
        
        # Check if daemon is running
        # CRITICAL: Pattern is already interpolated in Nix, so we can use it directly in pgrep
        # escapeShellArg would break pgrep pattern matching (adds quotes/escapes that pgrep doesn't understand)
        # The pattern is trusted (comes from Nix config), so direct interpolation is safe
        DAEMON_RUNNING=false
        PGREP_RESULT=$(${pkgs.procps}/bin/pgrep $PGREP_FLAG "${daemon.pattern}" 2>&1 || echo "")
        if [ -n "$PGREP_RESULT" ]; then
          DAEMON_RUNNING=true
          # #region agent log
          if [ "${daemon.name}" = "waybar" ]; then
            echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:waybar-running\",\"message\":\"Waybar is running\",\"data\":{\"daemon\":\"${daemon.name}\",\"pattern\":\"${daemon.pattern}\",\"pgrepResult\":\"$PGREP_RESULT\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          fi
          # #endregion
        else
          # #region agent log
          if [ "${daemon.name}" = "waybar" ]; then
            # Check what waybar processes actually exist
            ALL_WAYBAR=$(pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
            echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:waybar-not-found\",\"message\":\"Waybar pattern not found\",\"data\":{\"daemon\":\"${daemon.name}\",\"pattern\":\"${daemon.pattern}\",\"pgrepFlag\":\"$PGREP_FLAG\",\"pgrepResult\":\"$PGREP_RESULT\",\"allWaybarProcs\":\"$ALL_WAYBAR\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          fi
          # #endregion
        fi
        
        # Additional check for waybar: verify the main process is actually running (not just child processes)
        # CRITICAL: Use the exact pattern from daemon definition (with full store path) for consistency
        if [ "${daemon.name}" = "waybar" ] && [ "$DAEMON_RUNNING" = "false" ]; then
          # Check if any waybar process is running (might be child processes)
          if ${pkgs.procps}/bin/pgrep -f "waybar" > /dev/null 2>&1; then
            # Waybar processes exist, but main process might have crashed
            # CRITICAL: Use the exact pattern from daemon definition (not a simplified fallback)
            # This ensures we match the same process that daemon-manager would match
            if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "${daemon.pattern}" > /dev/null 2>&1; then
              DAEMON_RUNNING=true
              log "INFO: ${daemon.name} main process is running (matched with pattern: ${daemon.pattern})" "info"
            fi
          fi
        fi
        
        # Strike system for waybar: require 3 consecutive failures (90 seconds) before restart
        # This prevents false positives from temporary pgrep failures or process state transitions
        if [ "${daemon.name}" = "waybar" ]; then
          if [ "$DAEMON_RUNNING" = "false" ]; then
            WAYBAR_FAILURE_COUNT=$((WAYBAR_FAILURE_COUNT + 1))
            log "Waybar pattern not found (failure count: $WAYBAR_FAILURE_COUNT)" "warning"
            
            # Only proceed with restart if we've seen 3 consecutive failures (90 seconds total)
            if [ "$WAYBAR_FAILURE_COUNT" -lt 3 ]; then
              # Skip restart, wait for next check cycle (30 seconds later)
              log "Waybar strike system: Skipping restart (failure count: $WAYBAR_FAILURE_COUNT/3)" "info"
              continue
            else
              # Reset counter before restart attempt
              log "Waybar strike system: Threshold reached (3 failures), proceeding with restart" "warning"
              WAYBAR_FAILURE_COUNT=0
              # Fall through to existing restart logic below
            fi
          else
            # Waybar is running - reset failure count if it was non-zero
            if [ "$WAYBAR_FAILURE_COUNT" -gt 0 ]; then
              log "Waybar recovered (was down for $WAYBAR_FAILURE_COUNT checks)" "info"
              WAYBAR_FAILURE_COUNT=0
            fi
          fi
        fi
        
        if [ "$DAEMON_RUNNING" = "false" ]; then
          RESTART_COUNT=$(get_restart_count "${daemon.name}")
          
          # For waybar, capture detailed state before restart
          if [ "${daemon.name}" = "waybar" ]; then
            ALL_WAYBAR_PROCS_HM=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
            WAYBAR_STDERR_LOG="/tmp/daemon-waybar_-c-stderr.log"
            WAYBAR_STDERR_CONTENT=""
            if [ -f "$WAYBAR_STDERR_LOG" ]; then
              WAYBAR_STDERR_CONTENT=$(cat "$WAYBAR_STDERR_LOG" 2>/dev/null | tail -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
            fi
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:waybar-down-detected\",\"message\":\"Waybar not running, checking before restart\",\"data\":{\"daemon\":\"${daemon.name}\",\"pattern\":\"${daemon.pattern}\",\"restartCount\":\"$RESTART_COUNT\",\"allWaybarProcs\":\"$ALL_WAYBAR_PROCS_HM\",\"stderrBase64\":\"$WAYBAR_STDERR_CONTENT\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
          fi
          
          # Exponential backoff: skip restart if too many attempts (max 3 attempts = 90 seconds)
          if [ "$RESTART_COUNT" -ge 3 ]; then
            log "WARNING: ${daemon.name} crashed but restart limit reached (''${RESTART_COUNT} attempts). Skipping restart." "warning"
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:restart-limit\",\"message\":\"Restart limit reached\",\"data\":{\"daemon\":\"${daemon.name}\",\"restartCount\":\"$RESTART_COUNT\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
            continue
          fi
          
          log "WARNING: ${daemon.name} is not running (restart attempt: $((RESTART_COUNT + 1)))" "warning"
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:daemon-down\",\"message\":\"Daemon not running, attempting restart\",\"data\":{\"daemon\":\"${daemon.name}\",\"pattern\":\"${daemon.pattern}\",\"restartAttempt\":\"$((RESTART_COUNT + 1))\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
          
          # Attempt to restart the daemon
          ${daemon-manager}/bin/daemon-manager \
            ${lib.strings.escapeShellArg daemon.pattern} \
            ${lib.strings.escapeShellArg daemon.match_type} \
            ${lib.strings.escapeShellArg daemon.command} \
            ${lib.strings.escapeShellArg (if daemon.reload != "" then daemon.reload else "")} \
            ${if daemon.requires_sway then "true" else "false"} \
            ${if daemon.requires_tray or false then "true" else "false"}
          
          RESTART_EXIT_CODE=$?
          # #region agent log
          echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:restart-attempt\",\"message\":\"Restart command executed\",\"data\":{\"daemon\":\"${daemon.name}\",\"exitCode\":\"$RESTART_EXIT_CODE\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
          # #endregion
          
          if [ $RESTART_EXIT_CODE -eq 0 ]; then
            # Check if restart was successful
            # CRITICAL: For waybar, wait longer (5 seconds) to catch crashes after Wayland initialization
            if [ "${daemon.name}" = "waybar" ]; then
              sleep 5
            else
              sleep 2
            fi
            if ${pkgs.procps}/bin/pgrep $PGREP_FLAG "${daemon.pattern}" > /dev/null 2>&1; then
              log "SUCCESS: ${daemon.name} restarted successfully" "info"
              # #region agent log
              echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:restart-success\",\"message\":\"Daemon restarted successfully\",\"data\":{\"daemon\":\"${daemon.name}\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
              # #endregion
              reset_restart_count "${daemon.name}"
            else
              log "ERROR: ${daemon.name} restart failed" "err"
              
              # For waybar, capture detailed failure state
              if [ "${daemon.name}" = "waybar" ]; then
                WAYBAR_STDERR_LOG_FAIL="/tmp/daemon-waybar_-c-stderr.log"
                WAYBAR_STDERR_FAIL=""
                if [ -f "$WAYBAR_STDERR_LOG_FAIL" ]; then
                  WAYBAR_STDERR_FAIL=$(cat "$WAYBAR_STDERR_LOG_FAIL" 2>/dev/null | tail -100 | ${pkgs.coreutils}/bin/base64 -w 0 2>/dev/null || echo "")
                fi
                ALL_WAYBAR_PROCS_FAIL=$(${pkgs.procps}/bin/pgrep -f "waybar" 2>/dev/null | tr '\n' ',' || echo "none")
                # #region agent log
                echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:restart-failed\",\"message\":\"Waybar restart failed (not running after check)\",\"data\":{\"daemon\":\"${daemon.name}\",\"pattern\":\"${daemon.pattern}\",\"waitTime\":\"5s\",\"allWaybarProcs\":\"$ALL_WAYBAR_PROCS_FAIL\",\"stderrBase64\":\"$WAYBAR_STDERR_FAIL\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
                # #endregion
              else
                # #region agent log
                echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:restart-failed\",\"message\":\"Daemon restart failed (not running after check)\",\"data\":{\"daemon\":\"${daemon.name}\",\"pattern\":\"${daemon.pattern}\",\"waitTime\":\"2s\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
                # #endregion
              fi
              increment_restart_count "${daemon.name}"
            fi
          else
            log "ERROR: ${daemon.name} restart command failed" "err"
            # #region agent log
            echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:restart-cmd-failed\",\"message\":\"Restart command failed\",\"data\":{\"daemon\":\"${daemon.name}\",\"exitCode\":\"$RESTART_EXIT_CODE\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            # #endregion
            increment_restart_count "${daemon.name}"
          fi
        else
          # Daemon is running - reset restart count
          RESTART_COUNT=$(get_restart_count "${daemon.name}")
          if [ "$RESTART_COUNT" -gt 0 ]; then
            log "INFO: ${daemon.name} is healthy again (was restarted ''${RESTART_COUNT} times)" "info"
            # #region agent log
            if [ "${daemon.name}" = "waybar" ]; then
              echo "{\"timestamp\":$(date +%s000),\"location\":\"health-monitor:daemon-healthy\",\"message\":\"Daemon is healthy\",\"data\":{\"daemon\":\"${daemon.name}\",\"wasRestarted\":\"$RESTART_COUNT\",\"hypothesisId\":\"B\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\"}" >> /home/akunito/.dotfiles/.cursor/debug.log 2>/dev/null || true
            fi
            # #endregion
            reset_restart_count "${daemon.name}"
          fi
        fi
      '') daemons}
    done
  '';
in {

  imports = [
    ../../app/terminal/alacritty.nix
    ../../app/terminal/kitty.nix
    ../../app/terminal/tmux.nix
    ../../app/gaming/mangohud.nix
    ../../app/ai/aichat.nix
    ../../shell/sh.nix
  ];

  # CRITICAL: Portal configuration to avoid conflicts with KDE
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
    config = {
      sway = {
        default = [ "wlr" "gtk" ];
      };
    };
  };

  # CRITICAL: Idle daemon with swaylock-effects
  services.swayidle = {
    enable = true;
    timeouts = [
      {
        timeout = 600; # 10 minutes
        command = "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";
      }
      {
        timeout = 900; # 15 minutes
        command = "${pkgs.sway}/bin/swaymsg 'output * dpms off'";
        resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * dpms on'";
      }
    ];
    # New syntax: events is now an attrset keyed by event name, value is the command string
    events = {
      "before-sleep" = "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033";
    };
  };

  # Clipboard history is now handled via cliphist in startup commands

  # SwayFX configuration
  wayland.windowManager.sway = {
    enable = true;
    package = pkgs.swayfx;  # Use SwayFX instead of standard sway
    checkConfig = false;  # Disable config check (fails in build sandbox without DRM FD)
    
    config = {
      # Hyper key definition (Ctrl+Alt+Super)
      modifier = "Mod4"; # Super key
      # Note: Hyper key combinations are defined directly in keybindings
      # $hyper = Mod4+Control+Mod1 (used in keybindings)

      # Standard Sway settings (border, gaps, and workspace settings moved to extraConfig)
      gaps = {
        inner = 8;
      };

      # Keybindings
      keybindings = lib.mkMerge [
        {
          # Reload SwayFX configuration
          "${hyper}+Shift+r" = "reload";
          
          # Rofi Universal Launcher
          "${hyper}+space" = "exec rofi -show combi -combi-modi 'drun,run,window' -show-icons";
          "${hyper}+BackSpace" = "exec rofi -show combi -combi-modi 'drun,run,window' -show-icons";
          # Note: Removed "${hyper}+d" to avoid conflict with application bindings
          # Use "${hyper}+space" or "${hyper}+BackSpace" for rofi launcher
          
          # Window Overview (Mission Control-like)
          # Using Rofi in window mode with grid layout for stable workspace overview
          # Grid layout: 3 columns, large icons (48px), vertical orientation
          # Rofi inherits Stylix colors automatically via existing rofi.nix configuration
          "${hyper}+Tab" = "exec rofi -show window -theme-str 'window {width: 60%;} listview {columns: 3; lines: 6; fixed-height: true;} element {orientation: vertical; padding: 10px;} element-icon {size: 48px;}'";
          
          # Workspace toggle (back and forth)
          "Mod4+Tab" = "workspace back_and_forth";
          
          # Screenshot workflow
          "${hyper}+Shift+x" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh full";
          "${hyper}+Shift+c" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          "Print" = "exec ${config.home.homeDirectory}/.config/sway/scripts/screenshot.sh area";
          
          # Application keybindings (using app-toggle.sh script)
          # Note: Using different keys to avoid conflicts with window management bindings
          # Format: app-toggle.sh <app_id|class> <launch_command...>
          "${hyper}+T" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh kitty kitty";
          "${hyper}+R" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Alacritty alacritty";
          "${hyper}+L" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh org.telegram.desktop Telegram";
          "${hyper}+E" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh io.dbeaver.DBeaverCommunity dbeaver";
          "${hyper}+D" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh obsidian obsidian --no-sandbox --ozone-platform=wayland --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations";
          "${hyper}+V" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.vivaldi.Vivaldi vivaldi";
          "${hyper}+G" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh chromium-browser chromium";
          "${hyper}+Y" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh spotify spotify --enable-features=UseOzonePlatform --ozone-platform=wayland";
          "${hyper}+N" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh nwg-look nwg-look";
          "${hyper}+P" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh Bitwarden bitwarden";
          "${hyper}+C" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh cursor cursor --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto --unity-launch";
          "${hyper}+M" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh mission-center mission-center";
          "${hyper}+B" = "exec ${config.home.homeDirectory}/.config/sway/scripts/app-toggle.sh com.usebottles.bottles bottles";
          
          # Workspace navigation (using Sway native commands for local cycling)
          "${hyper}+Q" = "workspace prev_on_output";  # LOCAL navigation (within current monitor only)
          "${hyper}+W" = "workspace next_on_output";  # LOCAL navigation (within current monitor only)
          "${hyper}+Shift+Q" = "move container to workspace prev_on_output";  # Move window to previous workspace on current monitor (LOCAL)
          "${hyper}+Shift+W" = "move container to workspace next_on_output";  # Move window to next workspace on current monitor (LOCAL)
          
          # Direct workspace bindings (using swaysome)
          "${hyper}+1" = "exec swaysome focus 1";
          "${hyper}+2" = "exec swaysome focus 2";
          "${hyper}+3" = "exec swaysome focus 3";
          "${hyper}+4" = "exec swaysome focus 4";
          "${hyper}+5" = "exec swaysome focus 5";
          "${hyper}+6" = "exec swaysome focus 6";
          "${hyper}+7" = "exec swaysome focus 7";
          "${hyper}+8" = "exec swaysome focus 8";
          "${hyper}+9" = "exec swaysome focus 9";
          "${hyper}+0" = "exec swaysome focus 10";
          
          # Move window to workspace 1-10 (using swaysome)
          "${hyper}+Shift+1" = "exec swaysome move 1";
          "${hyper}+Shift+2" = "exec swaysome move 2";
          "${hyper}+Shift+3" = "exec swaysome move 3";
          "${hyper}+Shift+4" = "exec swaysome move 4";
          "${hyper}+Shift+5" = "exec swaysome move 5";
          "${hyper}+Shift+6" = "exec swaysome move 6";
          "${hyper}+Shift+7" = "exec swaysome move 7";
          "${hyper}+Shift+8" = "exec swaysome move 8";
          "${hyper}+Shift+9" = "exec swaysome move 9";
          "${hyper}+Shift+0" = "exec swaysome move 10";
          
          # Move window between monitors
          "${hyper}+Shift+Left" = "move container to output left";
          "${hyper}+Shift+Right" = "move container to output right";
          
          # Output focus bindings (required since F-keys are removed)
          "${hyper}+Left" = "focus output left";
          "${hyper}+Right" = "focus output right";
          "${hyper}+Up" = "focus output up";
          "${hyper}+Down" = "focus output down";
          
          # Window management (basic - keeping for compatibility)
          "${hyper}+h" = "focus left";
          "${hyper}+j" = "focus down";
          "${hyper}+k" = "focus up";
          # Note: Removed "${hyper}+l" to avoid conflict with "${hyper}+L" (telegram)
          "${hyper}+f" = "fullscreen toggle";
          "${hyper}+Shift+space" = "floating toggle";
          # Note: Removed "${hyper}+s" to avoid conflict with layout bindings
          # Note: Removed "${hyper}+w" to avoid conflict with "${hyper}+W" (workspace next)
          # Note: Removed "${hyper}+e" to avoid conflict with "${hyper}+E" (dolphin)
          
          # Window movement (conditional - floating vs tiled)
          "${hyper}+Shift+j" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh left";
          "${hyper}+colon" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh right";
          "${hyper}+Shift+k" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh down";
          "${hyper}+Shift+l" = "exec ${config.home.homeDirectory}/.config/sway/scripts/window-move.sh up";
          
          # Window focus navigation
          "${hyper}+Shift+comma" = "focus left";  # Changed from Shift+m to avoid conflict with mission-center
          "${hyper}+question" = "focus right";
          "${hyper}+less" = "focus down";
          "${hyper}+greater" = "focus up";
          
          # Window resizing
          "${hyper}+Shift+u" = "resize shrink width 5 ppt";
          "${hyper}+Shift+p" = "resize grow width 5 ppt";
          "${hyper}+Shift+i" = "resize grow height 5 ppt";
          "${hyper}+Shift+o" = "resize shrink height 5 ppt";
          
          # Window management toggles
          "${hyper}+Escape" = "kill";
          "${hyper}+Shift+f" = "floating toggle";
          "${hyper}+Shift+s" = "sticky toggle";
          "${hyper}+Shift+g" = "fullscreen toggle";
          
          # Scratchpad
          "${hyper}+minus" = "scratchpad show";
          "${hyper}+Shift+minus" = "move scratchpad";
          
          # Clipboard history
          "${hyper}+Shift+v" = "exec sh -c '${pkgs.cliphist}/bin/cliphist list | ${pkgs.rofi}/bin/rofi -dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy'";
          
          # Power menu
          "${hyper}+Shift+BackSpace" = "exec ${config.home.homeDirectory}/.config/sway/scripts/power-menu.sh";
          
          # Toggle SwayFX default bar (swaybar) - disabled by default, can be toggled manually
          "${hyper}+Shift+Home" = "exec ${config.home.homeDirectory}/.config/sway/scripts/swaybar-toggle.sh";
          
          # Hide window (move to scratchpad)
          "${hyper}+Shift+e" = "move scratchpad";
          
          # Exit Sway
          "${hyper}+Shift+End" = "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit Sway? This will end your Wayland session.' -b 'Yes, exit Sway' 'swaymsg exit'";
        }
      ];

      # Startup commands (daemons)
      startup = [
        # Initialize swaysome and assign workspace groups to monitors
        # No 'always = true' - runs only on initial startup, not on config reload
        # This prevents jumping back to empty workspaces when editing config
        {
          command = "${config.home.homeDirectory}/.config/sway/scripts/swaysome-init.sh";
        }
        # CRITICAL: Set dark mode environment variables for GTK and Qt apps (both XWayland and Wayland native)
        {
          command = "bash -c 'export GTK_APPLICATION_PREFER_DARK_THEME=1; export GTK_THEME=Adwaita-dark; gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true; gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark 2>/dev/null || true; dbus-update-activation-environment --systemd GTK_APPLICATION_PREFER_DARK_THEME GTK_THEME'";
          always = true;
        }
        # Unified daemon management - starts all daemons with smart reload support
        # Note: Wallpaper (swaybg) is handled by the unified daemon manager
        # CRITICAL: Ensure no 'output * bg' commands exist in config to avoid duplicate wallpaper processes
        {
          command = "${start-sway-daemons}/bin/start-sway-daemons";
          always = true;
        }
        # Sanity check after startup - verifies all daemons started successfully
        # Only runs on initial startup (not on reload) to avoid unnecessary checks
        {
          command = "${daemon-sanity-check}/bin/daemon-sanity-check --fix";
          always = false;  # Only run on initial startup, not on reload
        }
        # Daemon health monitor - periodically checks and restarts crashed daemons
        # Runs continuously in background (not managed by daemon-manager to avoid circular dependency)
        {
          command = "${daemon-health-monitor}/bin/daemon-health-monitor";
          always = false;  # Only run on initial startup, not on reload
        }
        # DESK-only startup apps (runs after daemons are ready)
        {
          command = "${desk-startup-apps-script}/bin/desk-startup-apps";
          always = false;  # Only run on initial startup, not on config reload
        }
      ];

      # Window rules
      window = {
        commands = [
          # Wayland apps (use app_id)
          { criteria = { app_id = "rofi"; }; command = "floating enable"; }
          { criteria = { app_id = "kitty"; }; command = "floating enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "floating enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "floating enable"; }
          { criteria = { app_id = "com.usebottles.bottles"; }; command = "floating enable"; }
          { criteria = { app_id = "swayfx-settings"; }; command = "floating enable"; }
          
          # XWayland apps (use class)
          { criteria = { class = "Spotify"; }; command = "floating enable"; }
          { criteria = { class = "Dolphin"; }; command = "floating enable"; }
          { criteria = { class = "dolphin"; }; command = "floating enable"; }
          
          # Dolphin on Wayland (use app_id)
          { criteria = { app_id = "org.kde.dolphin"; }; command = "floating enable"; }
          
          # Sticky windows - visible on all workspaces of their monitor
          { criteria = { app_id = "kitty"; }; command = "sticky enable"; }
          { criteria = { app_id = "Alacritty"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.telegram.desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "telegram-desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "bitwarden"; }; command = "sticky enable"; }
          { criteria = { app_id = "bitwarden-desktop"; }; command = "sticky enable"; }
          { criteria = { app_id = "Bitwarden"; }; command = "sticky enable"; }
          { criteria = { app_id = "org.kde.dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "Dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "dolphin"; }; command = "sticky enable"; }
          { criteria = { class = "Spotify"; }; command = "sticky enable"; }
          
        ];
      };
    };

    extraConfig = ''
      # Window border settings
      default_border pixel 2
      
      # Disable SwayFX's default internal bar (swaybar) by default
      # Can be toggled manually via ${hyper}+Shift+Home keybinding or: swaymsg bar mode dock/invisible
      bar {
        mode invisible
        hidden_state hide
        position bottom
      }
      
      # CRITICAL: Alt key for Plasma-like window manipulation
      # Alt+drag moves windows, Alt+right-drag resizes windows
      floating_modifier Mod1
      
      # Monitor configuration with scaling and positioning
      # DP-1: Samsung Odyssey G70NC (4K: 3840x2160) - Primary monitor
      # DP-2: NSL RGB-27QHDS (2K: 2560x1440) - Secondary monitor (portrait, right side)
      # Calculations:
      # - DP-1: 3840x2160 @ scale 1.6 = logical 2400x1350
      # - DP-2: 2560x1440 rotated 90° = 1440x2560 @ scale 1.15 = logical 1252x2226
      # - To align bottoms: DP-1 bottom at y=1350, DP-2 bottom should be at y=1350
      # - DP-2 top at y=1350-2226=-876 (extends above DP-1, which is fine)
      # - DP-2 x position: right of DP-1 = 2400
      output "DP-1" {
          scale 1.6
          position 0,0
      }
      output "DP-2" {
          mode 2560x1440@144.000Hz
          scale 1.25
          transform 90
          position 2400,-876
      }
      
      # DP-3 (BenQ): Position left of DP-1
      # Position: negative x to place it left of DP-1
      output "DP-3" {
          position -1920,0
      }
      
      # HDMI-A-1 (Philips): Position right of DP-2
      # DP-2 logical width: 1252, so HDMI-A-1 x = 2400 + 1252 = 3652
      # Align vertically with DP-2 (y = -876 or adjust for alignment)
      output "HDMI-A-1" {
          position 3652,-876
      }
      
      # Workspace-to-monitor assignments with fallbacks
      # DP-1 (Samsung 4K): Workspaces 1-10
      workspace 1 output DP-1
      workspace 2 output DP-1
      workspace 3 output DP-1
      workspace 4 output DP-1
      workspace 5 output DP-1
      workspace 6 output DP-1
      workspace 7 output DP-1
      workspace 8 output DP-1
      workspace 9 output DP-1
      workspace 10 output DP-1
      
      # DP-2 (NSL 2K): Workspaces 11-15 (fallback to DP-1 if DP-2 disconnected)
      workspace 11 output DP-2 DP-1
      workspace 12 output DP-2 DP-1
      workspace 13 output DP-2 DP-1
      workspace 14 output DP-2 DP-1
      workspace 15 output DP-2 DP-1
      
      # DP-3 (BenQ): Workspace 21 (fallback to DP-1 if DP-3 disconnected)
      workspace 21 output DP-3 DP-1
      
      # HDMI-A-1 (Philips): Workspace 31 (fallback to DP-1 if HDMI-A-1 disconnected)
      workspace 31 output HDMI-A-1 DP-1
      
      # Workspace configuration
      workspace_auto_back_and_forth yes
      
      # DESK startup apps - assign to specific workspaces
      # Using 'assign' instead of 'for_window' prevents flickering on wrong workspace
      assign [app_id="com.vivaldi.Vivaldi"] workspace number 1
      assign [app_id="cursor"] workspace number 2
      assign [app_id="obsidian"] workspace number 11
      assign [app_id="chromium"] workspace number 12
      assign [class="chromium-browser"] workspace number 12
      
      # Disable SwayFX's default internal bar (swaybar) by default
      # Can be toggled manually via swaybar-toggle.sh script or keybinding
      bar bar-0 {
        mode invisible
        hidden_state hide
      }
      
      # SwayFX visual settings matching Khanelinix aesthetic (blur, shadows, rounded corners)
      corner_radius 12
      blur enable
      blur_xray disable
      blur_passes 3
      blur_radius 5
      shadows enable
      shadow_blur_radius 20
      shadow_color #00000070
      
      # Dim inactive windows slightly for focus
      default_dim_inactive 0.1
      
      # Layer effects (Blur the Waybar)
      # CRITICAL: Split into separate lines if chaining not supported
      # NOTE: Previous config had layer_effects commented out due to segfault in SwayFX 0.5.3
      # Test if current SwayFX version supports layer_effects
      # If not supported, blur will still work for windows
      layer_effects "waybar" blur enable
      layer_effects "waybar" corner_radius 12
      layer_effects "waybar" blur enable
      layer_effects "waybar" corner_radius 12
      
      # Keyboard input configuration for polyglot typing (English/Spanish)
      input "type:keyboard" {
        xkb_layout "us"
        xkb_variant "altgr-intl"
      }
      
      # Touchpad configuration
      input "type:touchpad" {
        dwt enabled
        tap enabled
        natural_scroll enabled
        middle_emulation enabled
      }
      
      # Additional SwayFX configuration
      # Floating window rules (duplicate from config.window.commands for reliability)
      for_window [app_id="kitty"] floating enable
      for_window [app_id="org.telegram.desktop"] floating enable
      for_window [app_id="telegram-desktop"] floating enable
      for_window [app_id="bitwarden"] floating enable
      for_window [app_id="bitwarden-desktop"] floating enable
      for_window [app_id="Bitwarden"] floating enable
      for_window [app_id="com.usebottles.bottles"] floating enable
      for_window [app_id="org.kde.dolphin"] floating enable
      for_window [class="Dolphin"] floating enable
      for_window [class="dolphin"] floating enable
      for_window [app_id="rofi"] floating enable
      for_window [app_id="swayfx-settings"] floating enable
      
      # Alacritty: floating and sticky (case variations)
      for_window [app_id="Alacritty"] floating enable, sticky enable
      for_window [app_id="alacritty"] floating enable, sticky enable
      
      # Spotify: floating and sticky (both XWayland and Wayland)
      for_window [class="Spotify"] floating enable, sticky enable
      for_window [app_id="spotify"] floating enable, sticky enable
      
      # Additional floating window rules
      for_window [app_id="pavucontrol"] floating enable
      for_window [app_id="nm-connection-editor"] floating enable
      for_window [app_id="blueman-manager"] floating enable
      for_window [app_id="swappy"] floating enable
      for_window [app_id="swaync"] floating enable
      
      # Focus follows mouse
      focus_follows_mouse yes
      
      # Mouse warping
      mouse_warping output
    '';
  };



  # Btop theme configuration (Stylix colors)
  # CRITICAL: Check if Stylix is actually available (not just enabled)
  # Stylix is disabled for Plasma 6 even if stylixEnable is true
  # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
  home.file.".config/btop/btop.conf" = lib.mkIf (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) {
    text = ''
      # Btop Configuration
      # Theme matching Stylix colors
      
      theme_background = "#${config.lib.stylix.colors.base00}"
      theme_text = "#${config.lib.stylix.colors.base07}"
      theme_title = "#${config.lib.stylix.colors.base0D}"
      theme_hi_fg = "#${config.lib.stylix.colors.base0A}"
      theme_selected_bg = "#${config.lib.stylix.colors.base0D}"
      theme_selected_fg = "#${config.lib.stylix.colors.base07}"
      theme_cpu_box = "#${config.lib.stylix.colors.base0B}"
      theme_mem_box = "#${config.lib.stylix.colors.base0E}"
      theme_net_box = "#${config.lib.stylix.colors.base0C}"
      theme_proc_box = "#${config.lib.stylix.colors.base09}"
    '';
  };

  # Libinput-gestures configuration for SwayFX
  # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)
  # Uses next_on_output/prev_on_output to prevent gestures from jumping between monitors
  xdg.configFile."libinput-gestures.conf".text = ''
    # Libinput-gestures configuration for SwayFX
    # 3-finger swipe for workspace navigation (matches keybindings: next_on_output/prev_on_output)
    
    gesture swipe left 3 ${pkgs.swayfx}/bin/swaymsg workspace next_on_output
    gesture swipe right 3 ${pkgs.swayfx}/bin/swaymsg workspace prev_on_output
    # Optional: 3-finger swipe up for fullscreen toggle
    # gesture swipe up 3 ${pkgs.swayfx}/bin/swaymsg fullscreen toggle
  '';

  # Install scripts to .config/sway/scripts/
  home.file.".config/sway/scripts/screenshot.sh" = {
    source = ./scripts/screenshot.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/ssh-smart.sh" = {
    source = ./scripts/ssh-smart.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/app-toggle.sh" = {
    source = ./scripts/app-toggle.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/window-move.sh" = {
    source = ./scripts/window-move.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/power-menu.sh" = {
    source = ./scripts/power-menu.sh;
    executable = true;
  };
  
  home.file.".config/sway/scripts/swaysome-init.sh" = {
    source = ./scripts/swaysome-init.sh;
    executable = true;
  };
  
  # Generate swaybar-toggle script with proper package paths
  home.file.".config/sway/scripts/swaybar-toggle.sh" = {
    text = ''
      #!/bin/sh
      # Toggle SwayFX's default bar (swaybar) visibility
      # The bar is disabled by default in the config (mode invisible)
      # This script allows manual toggling when needed

      # Get current bar mode
      CURRENT_MODE=$(${pkgs.swayfx}/bin/swaymsg -t get_bar_config bar-0 | ${pkgs.jq}/bin/jq -r '.mode' 2>/dev/null)

      if [ "$CURRENT_MODE" = "invisible" ] || [ -z "$CURRENT_MODE" ]; then
        # Bar is invisible or doesn't exist - show it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode dock
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar enabled (dock mode)" || true
      else
        # Bar is visible - hide it
        ${pkgs.swayfx}/bin/swaymsg bar bar-0 mode invisible
        # Optional notification (fails gracefully if libnotify not available)
        command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Swaybar" "Bar disabled (invisible mode)" || true
      fi
    '';
    executable = true;
  };
  
  # NOTE: waybar-startup.sh and dock-diagnostic.sh have been removed
  # They were orphaned scripts superseded by daemon-manager
  # waybar-startup.sh functionality is now in daemon-manager
  # dock-diagnostic.sh was diagnostic-only and not used in startup
  
  # Add generated daemon management scripts to PATH
  home.packages = [
    daemon-manager
    start-sway-daemons
    daemon-sanity-check
    daemon-health-monitor
    desk-startup-apps-script
  ] ++ (with pkgs; [
    # SwayFX and related
    swayfx
    swaylock-effects
    swayidle
    swaynotificationcenter
    waybar  # Waybar status bar (also configured via programs.waybar)
    swaysome  # Workspace namespace per monitor
    
    # Screenshot workflow
    grim
    slurp
    swappy
    swaybg  # Wallpaper manager
    
    # Universal launcher
    rofi  # rofi-wayland has been merged into rofi (as of 2025-09-06)
    
    # Gaming tools
    gamescope
    mangohud
    
    # AI workflow (aichat is installed via module)
    
    # Terminal and tools
    jq  # CRITICAL: Required for screenshot script
    wl-clipboard
    cliphist  # Clipboard history manager for Wayland
    
    # Touchpad gestures
    libinput-gestures
    
    # System tools
    networkmanagerapplet
    blueman
    polkit_gnome
    
    # System monitoring
    # btop is installed by system/hardware/gpu-monitoring.nix module
    # AMD profiles get btop-rocm, Intel/others get standard btop
  ]);
}



