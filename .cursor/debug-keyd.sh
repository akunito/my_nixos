#!/usr/bin/env bash
# Diagnostic script for keyd Caps Lock remapping debugging
# Logs to: /home/akunito/.dotfiles/.cursor/debug.log

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
SESSION_ID="debug-session-$(date +%s)"
RUN_ID="run1"

log() {
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data="$4"
  local timestamp=$(date +%s%3N)
  
  echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"${hypothesis_id}\"}" >> "$LOG_FILE"
}

# #region agent log
log "A" "debug-keyd.sh:start" "Diagnostic script started" "{\"script\":\"debug-keyd.sh\",\"pid\":$$}"
# #endregion

echo "=== keyd Diagnostic Script ==="
echo "Logging to: $LOG_FILE"
echo ""

# Hypothesis A: keyd service status
echo "[HYPOTHESIS A] Checking keyd service status..."
if systemctl is-active --quiet keyd; then
  SERVICE_STATUS="active"
else
  SERVICE_STATUS="inactive"
fi

if systemctl is-enabled --quiet keyd; then
  SERVICE_ENABLED="enabled"
else
  SERVICE_ENABLED="disabled"
fi

# #region agent log
log "A" "debug-keyd.sh:service_status" "keyd service status" "{\"active\":\"${SERVICE_STATUS}\",\"enabled\":\"${SERVICE_ENABLED}\"}"
# #endregion

echo "  Service active: $SERVICE_STATUS"
echo "  Service enabled: $SERVICE_ENABLED"

# Get recent keyd logs
echo ""
echo "[HYPOTHESIS A] Recent keyd service logs:"
RECENT_LOGS=$(journalctl -u keyd -n 20 --no-pager 2>&1 | head -20)
# #region agent log
log "A" "debug-keyd.sh:keyd_logs" "Recent keyd service logs" "{\"logs\":\"$(echo "$RECENT_LOGS" | jq -Rs .)\"}"
# #endregion
echo "$RECENT_LOGS"

# Hypothesis B: Keyboard device detection
echo ""
echo "[HYPOTHESIS B] Listing keyboard devices..."

# List input devices
INPUT_DEVICES=$(ls -la /dev/input/by-id/ 2>/dev/null | grep -i kbd || echo "No keyboard devices found")
# #region agent log
log "B" "debug-keyd.sh:input_devices" "Keyboard input devices" "{\"devices\":\"$(echo "$INPUT_DEVICES" | jq -Rs .)\"}"
# #endregion
echo "  Input devices by-id:"
echo "$INPUT_DEVICES"

# Check /proc/bus/input/devices
echo ""
echo "  Devices from /proc/bus/input/devices:"
KEYBOARD_DEVICES=$(grep -A 5 "Handlers.*kbd" /proc/bus/input/devices 2>/dev/null | head -30 || echo "Could not read /proc/bus/input/devices")
# #region agent log
log "B" "debug-keyd.sh:proc_devices" "Keyboard devices from proc" "{\"devices\":\"$(echo "$KEYBOARD_DEVICES" | jq -Rs .)\"}"
# #endregion
echo "$KEYBOARD_DEVICES"

# Check USB devices
echo ""
echo "  USB devices:"
USB_DEVICES=$(lsusb 2>/dev/null | grep -i "keyboard\|input\|hid" || echo "No USB keyboard devices found")
# #region agent log
log "B" "debug-keyd.sh:usb_devices" "USB keyboard devices" "{\"devices\":\"$(echo "$USB_DEVICES" | jq -Rs .)\"}"
# #endregion
echo "$USB_DEVICES"

# Hypothesis C: keyd configuration
echo ""
echo "[HYPOTHESIS C] Checking keyd configuration..."
if [ -f /etc/keyd/default.conf ]; then
  KEYD_CONFIG=$(cat /etc/keyd/default.conf)
  # #region agent log
  log "C" "debug-keyd.sh:keyd_config" "keyd configuration file" "{\"config\":\"$(echo "$KEYD_CONFIG" | jq -Rs .)\"}"
  # #endregion
  echo "  Configuration file exists:"
  echo "$KEYD_CONFIG"
else
  # #region agent log
  log "C" "debug-keyd.sh:keyd_config" "keyd configuration file missing" "{\"error\":\"Config file not found\"}"
  # #endregion
  echo "  Configuration file NOT found at /etc/keyd/default.conf"
fi

# Check if keyd is monitoring devices
echo ""
echo "[HYPOTHESIS C] Checking keyd active devices..."
if command -v keyd >/dev/null 2>&1; then
  KEYD_VERSION=$(keyd --version 2>&1 || echo "Could not get version")
  # #region agent log
  log "C" "debug-keyd.sh:keyd_version" "keyd version" "{\"version\":\"$KEYD_VERSION\"}"
  # #endregion
  echo "  keyd version: $KEYD_VERSION"
else
  # #region agent log
  log "C" "debug-keyd.sh:keyd_version" "keyd command not found" "{\"error\":\"keyd binary not in PATH\"}"
  # #endregion
  echo "  keyd command not found in PATH"
fi

# Hypothesis D: Keycode testing
echo ""
echo "[HYPOTHESIS D] Instructions for keycode testing:"
echo "  To test raw keycodes, run: sudo evtest"
echo "  Select your keyboard device, then press Caps Lock"
echo "  This will show if keyd is remapping the keycode"
# #region agent log
log "D" "debug-keyd.sh:keycode_instructions" "Keycode testing instructions" "{\"instruction\":\"Run evtest to see raw keycodes\"}"
# #endregion

# Hypothesis E: Sway key reception
echo ""
echo "[HYPOTHESIS E] Checking Sway configuration..."
if command -v swaymsg >/dev/null 2>&1; then
  if swaymsg -t get_version >/dev/null 2>&1; then
    SWAY_VERSION=$(swaymsg -t get_version 2>&1)
    # #region agent log
    log "E" "debug-keyd.sh:sway_version" "Sway is running" "{\"version\":\"$SWAY_VERSION\"}"
    # #endregion
    echo "  Sway is running: $SWAY_VERSION"
    
    # Check hyper key definition
    if [ -f ~/.config/sway/config ]; then
      HYPER_DEF=$(grep -i "hyper.*=" ~/.config/sway/config | head -3 || echo "Not found in config")
      # #region agent log
      log "E" "debug-keyd.sh:hyper_def" "Hyper key definition in Sway" "{\"definition\":\"$HYPER_DEF\"}"
      # #endregion
      echo "  Hyper key definition: $HYPER_DEF"
    fi
  else
    # #region agent log
    log "E" "debug-keyd.sh:sway_version" "Sway not running or socket not accessible" "{\"error\":\"Cannot connect to Sway\"}"
    # #endregion
    echo "  Sway is NOT running or socket not accessible"
  fi
else
  # #region agent log
  log "E" "debug-keyd.sh:sway_version" "swaymsg not found" "{\"error\":\"swaymsg not in PATH\"}"
  # #endregion
  echo "  swaymsg command not found"
fi

echo ""
echo "=== Diagnostic Complete ==="
echo "Now ready to test Caps Lock key press..."
echo ""

# #region agent log
log "ALL" "debug-keyd.sh:end" "Diagnostic script completed" "{\"status\":\"ready_for_keypress_test\"}"
# #endregion

