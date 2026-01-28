#!/usr/bin/env bash
# Test Caps Lock keycode on Logitech keyboard

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
SESSION_ID="debug-session-$(date +%s)"
RUN_ID="run2"

log() {
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data="$4"
  local timestamp=$(date +%s%3N)
  
  echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"${hypothesis_id}\"}" >> "$LOG_FILE"
}

echo "=== Testing Caps Lock Keycode ==="
echo "This will help identify what keycode the Logitech keyboard sends for Caps Lock"
echo ""

# Find Logitech keyboard device
LOGITECH_DEVICE=$(ls -la /dev/input/by-id/ | grep -i "logitech.*kbd" | head -1 | awk '{print $NF}' | xargs readlink -f 2>/dev/null || echo "")

if [ -z "$LOGITECH_DEVICE" ]; then
  # Try to find it another way
  LOGITECH_DEVICE=$(grep -l "Logitech.*Keyboard" /sys/class/input/event*/device/name 2>/dev/null | head -1 | sed 's|/device/name||' | sed 's|sys/class/input|dev/input|' || echo "")
fi

# #region agent log
log "D" "test-capslock.sh:device_search" "Searching for Logitech keyboard device" "{\"device\":\"$LOGITECH_DEVICE\"}"
# #endregion

if [ -z "$LOGITECH_DEVICE" ]; then
  echo "ERROR: Could not find Logitech keyboard device"
  echo "Available keyboard devices:"
  ls -la /dev/input/by-id/ | grep -i kbd
  # #region agent log
  log "D" "test-capslock.sh:device_not_found" "Logitech keyboard device not found" "{\"available_devices\":\"$(ls -la /dev/input/by-id/ | grep -i kbd | jq -Rs .)\"}"
  # #endregion
  exit 1
fi

echo "Found Logitech keyboard device: $LOGITECH_DEVICE"
# #region agent log
log "D" "test-capslock.sh:device_found" "Logitech keyboard device found" "{\"device_path\":\"$LOGITECH_DEVICE\"}"
# #endregion

echo ""
echo "Now testing with evtest..."
echo "Instructions:"
echo "1. Select the Logitech keyboard from the list (look for 'Logitech')"
echo "2. Press Caps Lock key"
echo "3. Note the keycode shown (should be KEY_CAPSLOCK or similar)"
echo "4. Press Ctrl+C to exit"
echo ""

# Check if running as root (needed for evtest)
if [ "$EUID" -ne 0 ]; then
  echo "NOTE: evtest requires root. Running with sudo..."
  echo "Press Caps Lock when evtest shows the device list and after selecting your keyboard"
  sudo evtest "$LOGITECH_DEVICE" 2>&1 | head -50
else
  evtest "$LOGITECH_DEVICE" 2>&1 | head -50
fi

# #region agent log
log "D" "test-capslock.sh:evtest_complete" "evtest completed" "{\"status\":\"test_done\"}"
# #endregion
