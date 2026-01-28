#!/usr/bin/env bash
# Test what keycodes are being sent and received
# This will help us understand if keyd is remapping correctly

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

echo "=== Testing Keycode Remapping ==="
echo ""
echo "This script will help us understand:"
echo "1. What keycode the Logitech keyboard sends (before keyd)"
echo "2. What keycode keyd outputs (after remapping)"
echo "3. What Sway receives"
echo ""

# Find the Logitech keyboard device
LOGITECH_DEVICE=$(ls -la /dev/input/by-id/ | grep -i "logitech.*kbd" | head -1 | awk '{print $NF}' | xargs -I {} readlink -f /dev/input/by-id/{})
if [ -z "$LOGITECH_DEVICE" ]; then
  echo "ERROR: Could not find Logitech keyboard device"
  # #region agent log
  log "D" "test-keycodes.sh:device_not_found" "Logitech keyboard device not found" "{\"error\":\"device_not_found\"}"
  # #endregion
  exit 1
fi

echo "Found Logitech keyboard device: $LOGITECH_DEVICE"
# #region agent log
log "D" "test-keycodes.sh:device_found" "Logitech keyboard device found" "{\"device\":\"$LOGITECH_DEVICE\"}"
# #endregion

# Check if we can use evtest (requires root)
if [ -r "$LOGITECH_DEVICE" ]; then
  echo ""
  echo "=== Testing with evtest (raw kernel events) ==="
  echo "Press Caps Lock on the Logitech keyboard now..."
  echo "This shows what the kernel receives BEFORE keyd remapping"
echo ""

  # Use timeout to avoid hanging
  timeout 10 evtest "$LOGITECH_DEVICE" 2>&1 | head -50 | tee /tmp/evtest-output.txt
  
  # #region agent log
  log "D" "test-keycodes.sh:evtest_output" "evtest output captured" "{\"output\":\"$(cat /tmp/evtest-output.txt | jq -Rs .)\"}"
  # #endregion
else
  echo "Cannot read $LOGITECH_DEVICE directly (needs root)"
  echo "Run: sudo evtest (then select the Logitech keyboard device)"
  # #region agent log
  log "D" "test-keycodes.sh:evtest_permission" "evtest requires root permissions" "{\"device\":\"$LOGITECH_DEVICE\"}"
  # #endregion
fi

# Test with wev (Wayland events - shows what Sway receives AFTER keyd)
echo ""
echo "=== Testing with wev (Wayland events - what Sway receives) ==="
if command -v wev >/dev/null 2>&1; then
  echo "Press Caps Lock on the Logitech keyboard now..."
  echo "This shows what Sway receives AFTER keyd remapping"
  echo ""
  
  timeout 10 wev 2>&1 | grep -i "caps\|lock\|key\|control\|alt\|meta\|super" | head -20 | tee /tmp/wev-output.txt
  
  # #region agent log
  log "E" "test-keycodes.sh:wev_output" "wev output captured" "{\"output\":\"$(cat /tmp/wev-output.txt | jq -Rs .)\"}"
  # #endregion
else
  echo "wev not available. Install with: nix-env -iA nixos.wev"
  # #region agent log
  log "E" "test-keycodes.sh:wev_not_available" "wev tool not available" "{\"error\":\"wev_not_installed\"}"
  # #endregion
fi

# Check keyd logs for any errors
echo ""
echo "=== Checking keyd logs for errors ==="
KEYD_ERRORS=$(journalctl -u keyd --since "5 minutes ago" --no-pager 2>&1 | grep -i "error\|fail\|warn" | tail -10)
if [ -n "$KEYD_ERRORS" ]; then
  echo "Found keyd errors/warnings:"
  echo "$KEYD_ERRORS"
    # #region agent log
  log "A" "test-keycodes.sh:keyd_errors" "keyd errors found" "{\"errors\":\"$(echo "$KEYD_ERRORS" | jq -Rs .)\"}"
    # #endregion
else
  echo "No keyd errors found"
  # #region agent log
  log "A" "test-keycodes.sh:keyd_errors" "No keyd errors" "{\"status\":\"ok\"}"
  # #endregion
fi

echo ""
echo "=== Test Complete ==="
# #region agent log
log "ALL" "test-keycodes.sh:end" "Keycode test completed" "{\"status\":\"complete\"}"
# #endregion
