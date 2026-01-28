#!/usr/bin/env bash
# Verify keyd remapping is working
# Test if Caps Lock is being remapped to C-A-M

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
SESSION_ID="debug-session-$(date +%s)"
RUN_ID="run3"

log() {
  local hypothesis_id="$1"
  local location="$2"
  local message="$3"
  local data="$4"
  local timestamp=$(date +%s%3N)
  
  echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"${SESSION_ID}\",\"runId\":\"${RUN_ID}\",\"hypothesisId\":\"${hypothesis_id}\"}" >> "$LOG_FILE"
}

echo "=== Verifying keyd Remapping ==="

# Check if keyd service needs restart
echo "[HYPOTHESIS C] Checking if keyd needs restart..."
KEYD_RESTART_NEEDED=false

# Check when keyboard was last connected vs when keyd started
KEYD_START_TIME=$(systemctl show keyd --property=ActiveEnterTimestamp --value 2>/dev/null || echo "")
KEYBOARD_CONNECT_TIME=$(journalctl -u keyd --no-pager 2>&1 | grep "046d:4075" | tail -1 | awk '{print $1, $2, $3}' || echo "")

# #region agent log
log "C" "verify-keyd.sh:timing" "Checking keyd and keyboard timing" "{\"keyd_start\":\"$KEYD_START_TIME\",\"keyboard_connect\":\"$KEYBOARD_CONNECT_TIME\"}"
# #endregion

# Check current keyd active devices
echo ""
echo "Current keyd active devices from logs:"
ACTIVE_DEVICES=$(journalctl -u keyd --since "1 hour ago" --no-pager 2>&1 | grep "DEVICE: match" | tail -5)
# #region agent log
log "B" "verify-keyd.sh:active_devices" "Currently active keyd devices" "{\"devices\":\"$(echo "$ACTIVE_DEVICES" | jq -Rs .)\"}"
# #endregion
echo "$ACTIVE_DEVICES"

# Check if Logitech keyboard is in the list
if echo "$ACTIVE_DEVICES" | grep -q "046d:4075"; then
  echo "✓ Logitech keyboard (046d:4075) is matched by keyd"
  # #region agent log
  log "B" "verify-keyd.sh:device_matched" "Logitech keyboard is matched by keyd" "{\"status\":\"matched\"}"
  # #endregion
else
  echo "✗ Logitech keyboard (046d:4075) NOT found in active devices"
  echo "  This suggests keyd may not be applying remapping to this keyboard"
  # #region agent log
  log "B" "verify-keyd.sh:device_not_matched" "Logitech keyboard not in active devices" "{\"status\":\"not_matched\",\"action\":\"may_need_restart\"}"
  # #endregion
  KEYD_RESTART_NEEDED=true
fi

# Test: Check if we can manually trigger keyd to reload
echo ""
echo "[HYPOTHESIS C] Testing keyd configuration reload..."
if systemctl reload keyd 2>&1; then
  echo "✓ keyd reloaded successfully"
  # #region agent log
  log "C" "verify-keyd.sh:reload_success" "keyd reloaded" "{\"status\":\"success\"}"
  # #endregion
  sleep 2
  # Check if Logitech appears in new logs
  NEW_MATCHES=$(journalctl -u keyd --since "10 seconds ago" --no-pager 2>&1 | grep "046d:4075" || echo "")
  if [ -n "$NEW_MATCHES" ]; then
    echo "✓ Logitech keyboard matched after reload"
    # #region agent log
    log "C" "verify-keyd.sh:reload_matched" "Logitech matched after reload" "{\"status\":\"matched_after_reload\"}"
    # #endregion
  else
    echo "✗ Logitech keyboard still not matched after reload"
    # #region agent log
    log "C" "verify-keyd.sh:reload_not_matched" "Logitech not matched after reload" "{\"status\":\"not_matched_after_reload\"}"
    # #endregion
  fi
else
  echo "✗ Failed to reload keyd"
  # #region agent log
  log "C" "verify-keyd.sh:reload_failed" "keyd reload failed" "{\"status\":\"failed\"}"
  # #endregion
fi

# Check keyd config syntax
echo ""
echo "[HYPOTHESIS C] Verifying keyd config syntax..."
if [ -f /etc/keyd/default.conf ]; then
  CONFIG_CONTENT=$(cat /etc/keyd/default.conf)
  if echo "$CONFIG_CONTENT" | grep -q "capslock.*C-A-M"; then
    echo "✓ Config contains capslock=C-A-M"
    # #region agent log
    log "C" "verify-keyd.sh:config_ok" "keyd config syntax is correct" "{\"status\":\"valid\"}"
    # #endregion
  else
    echo "✗ Config does not contain capslock=C-A-M"
    # #region agent log
    log "C" "verify-keyd.sh:config_invalid" "keyd config missing remapping" "{\"status\":\"invalid\"}"
    # #endregion
  fi
fi

# #region agent log
log "ALL" "verify-keyd.sh:end" "Verification complete" "{\"restart_needed\":\"$KEYD_RESTART_NEEDED\"}"
# #endregion

echo ""
echo "=== Verification Complete ==="
if [ "$KEYD_RESTART_NEEDED" = true ]; then
  echo "RECOMMENDATION: Try restarting keyd service: sudo systemctl restart keyd"
fi

