#!/usr/bin/env bash
# Monitor keypress events for Caps Lock debugging
# This script monitors what keycodes are being sent when Caps Lock is pressed

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

echo "=== Keypress Monitor ==="
echo "This will monitor key events. Press Caps Lock when ready."
echo "Press Ctrl+C to stop monitoring."
echo ""

# Check if wev is available (Wayland event viewer)
if command -v wev >/dev/null 2>&1; then
  echo "[HYPOTHESIS D] Using wev to monitor Wayland key events..."
  echo "  Press Caps Lock now, then press Ctrl+C to stop..."
  # #region agent log
  log "D" "monitor-keypress.sh:wev_start" "Starting wev monitoring" "{\"tool\":\"wev\"}"
  # #endregion
  
  # Run wev and capture output
  timeout 30 wev 2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -qi "caps\|lock\|key"; then
      # #region agent log
      log "D" "monitor-keypress.sh:wev_event" "Key event detected" "{\"event\":\"$(echo "$line" | jq -Rs .)\"}"
      # #endregion
      echo "[EVENT] $line"
    fi
  done
elif command -v wshowkeys >/dev/null 2>&1; then
  echo "[HYPOTHESIS D] Using wshowkeys to monitor key events..."
  echo "  Press Caps Lock now, then press Ctrl+C to stop..."
  # #region agent log
  log "D" "monitor-keypress.sh:wshowkeys_start" "Starting wshowkeys monitoring" "{\"tool\":\"wshowkeys\"}"
  # #endregion
  
  timeout 30 wshowkeys -m 2>&1 | while IFS= read -r line; do
    if echo "$line" | grep -qi "caps\|lock\|key"; then
      # #region agent log
      log "D" "monitor-keypress.sh:wshowkeys_event" "Key event detected" "{\"event\":\"$(echo "$line" | jq -Rs .)\"}"
      # #endregion
      echo "[EVENT] $line"
    fi
  done
else
  echo "[HYPOTHESIS D] wev/wshowkeys not available. Please run manually:"
  echo "  For Wayland: wev (or wshowkeys -m)"
  echo "  For raw events: sudo evtest (select keyboard device)"
  # #region agent log
  log "D" "monitor-keypress.sh:tools_unavailable" "Monitoring tools not available" "{\"error\":\"wev and wshowkeys not found\"}"
  # #endregion
fi

# #region agent log
log "ALL" "monitor-keypress.sh:end" "Keypress monitoring completed" "{\"status\":\"monitoring_done\"}"
# #endregion

