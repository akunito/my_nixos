#!/bin/sh
# Waybar startup script with comprehensive logging
# Logs to /home/akunito/.dotfiles/.cursor/debug.log

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
TIMESTAMP=$(date +%s)

# Function to log JSON
log_json() {
  echo "{\"id\":\"log_${TIMESTAMP}_$(date +%N)\",\"timestamp\":$(date +%s)000,\"location\":\"waybar-startup.sh:$1\",\"message\":\"$2\",\"data\":$3,\"sessionId\":\"sway-debug\",\"runId\":\"startup\",\"hypothesisId\":\"$4\"}" >> "$LOG_FILE"
}

# #region agent log - Hypothesis A: Waybar binary check
WAYBAR_BIN=$(which waybar 2>/dev/null || echo "not_found")
WAYBAR_BIN_EXISTS=$(test -f "$WAYBAR_BIN" && echo "exists" || echo "not_found")
log_json "WAYBAR_BIN_CHECK" "Checking waybar binary" "{\"which_waybar\":\"$WAYBAR_BIN\",\"exists\":\"$WAYBAR_BIN_EXISTS\"}" "A"
# #endregion

# #region agent log - Hypothesis B: Waybar config check
WAYBAR_CONFIG_DIR="$HOME/.config/waybar"
if [ -f "$WAYBAR_CONFIG_DIR/config" ]; then
  WAYBAR_CONFIG_FILE="$WAYBAR_CONFIG_DIR/config"
  WAYBAR_CONFIG_ERROR=$(waybar --check-config 2>&1 || echo "config_error")
  log_json "WAYBAR_CONFIG_CHECK" "Checking waybar config syntax" "{\"config_file\":\"$WAYBAR_CONFIG_FILE\",\"error\":\"$WAYBAR_CONFIG_ERROR\"}" "B"
elif [ -f "$WAYBAR_CONFIG_DIR/config.json" ]; then
  WAYBAR_CONFIG_FILE="$WAYBAR_CONFIG_DIR/config.json"
  WAYBAR_CONFIG_ERROR=$(waybar --check-config 2>&1 || echo "config_error")
  log_json "WAYBAR_CONFIG_CHECK" "Checking waybar config syntax" "{\"config_file\":\"$WAYBAR_CONFIG_FILE\",\"error\":\"$WAYBAR_CONFIG_ERROR\"}" "B"
else
  log_json "WAYBAR_CONFIG_CHECK" "Waybar config file not found" "{\"config_dir\":\"$WAYBAR_CONFIG_DIR\",\"dir_exists\":$(test -d "$WAYBAR_CONFIG_DIR" && echo true || echo false)}" "B"
fi
# #endregion

# #region agent log - Hypothesis C: Waybar process check before start
WAYBAR_PROCESS_BEFORE=$(pgrep -x waybar || echo "not_running")
log_json "WAYBAR_PROCESS_BEFORE" "Checking if waybar is running before start" "{\"pid\":\"$WAYBAR_PROCESS_BEFORE\"}" "C"
# #endregion

# #region agent log - Hypothesis D: SwayFX readiness check
# Wait for SwayFX to be ready (max 10 seconds)
SWAY_READY=false
for i in $(seq 1 10); do
  if swaymsg -t get_version >/dev/null 2>&1; then
    SWAY_READY=true
    break
  fi
  sleep 1
done
SWAY_VERSION=$(swaymsg -t get_version 2>&1 || echo "swaymsg_failed")
log_json "SWAY_READY" "Checking if SwayFX is ready and responding" "{\"swaymsg_output\":\"$SWAY_VERSION\",\"ready\":\"$SWAY_READY\",\"waited_seconds\":\"$i\"}" "D"
# #endregion

# #region agent log - Hypothesis E: Environment variables check
log_json "ENV_VARS" "Checking critical environment variables" "{\"WAYLAND_DISPLAY\":\"${WAYLAND_DISPLAY:-not_set}\",\"XDG_RUNTIME_DIR\":\"${XDG_RUNTIME_DIR:-not_set}\",\"SWAYSOCK\":\"${SWAYSOCK:-not_set}\",\"PATH\":\"${PATH:0:200}\"}" "E"
# #endregion

# Kill any existing waybar processes (always kill to avoid duplicates)
log_json "WAYBAR_KILL" "Killing existing waybar processes" "{\"pid_before\":\"$WAYBAR_PROCESS_BEFORE\"}" "C"
pkill -x waybar 2>/dev/null
pkill -f "waybar" 2>/dev/null
sleep 1
WAYBAR_AFTER_KILL=$(pgrep -x waybar || echo "not_running")
log_json "WAYBAR_KILL_RESULT" "Waybar process after kill" "{\"pid_after_kill\":\"$WAYBAR_AFTER_KILL\"}" "C"

# Start waybar with error capture (non-blocking)
# #region agent log - Hypothesis C: Waybar start attempt
log_json "WAYBAR_START_CMD" "Executing waybar start command" "{\"binary\":\"$WAYBAR_BIN\"}" "C"
# Start waybar in background, redirect stderr to log file
# Use nohup and disown to ensure it runs independently
nohup waybar >> "$LOG_FILE" 2>&1 &
WAYBAR_START_PID=$!
disown $WAYBAR_START_PID 2>/dev/null || true
sleep 3
# #endregion

# #region agent log - Hypothesis C: Waybar process after start
WAYBAR_PROCESS_AFTER=$(pgrep -x waybar || echo "not_running")
WAYBAR_PS=$(ps aux | grep waybar | grep -v grep || echo "not_found")
log_json "WAYBAR_PROCESS_AFTER" "Checking waybar process after start" "{\"started_pid\":\"$WAYBAR_START_PID\",\"running_pid\":\"$WAYBAR_PROCESS_AFTER\",\"ps_output\":\"$WAYBAR_PS\"}" "C"
# #endregion

# #region agent log - Hypothesis C: Waybar window check
sleep 1
SWAY_TREE=$(swaymsg -t get_tree 2>/dev/null || echo "swaymsg_failed")
WAYBAR_WINDOW=$(echo "$SWAY_TREE" | jq -r '.. | select(.app_id? == "waybar") | {app_id,visible,rect,geometry}' 2>/dev/null || echo "no_window_or_jq_failed")
log_json "WAYBAR_WINDOW_CHECK" "Checking waybar window in sway tree" "{\"window_info\":\"$WAYBAR_WINDOW\"}" "C"
# #endregion


