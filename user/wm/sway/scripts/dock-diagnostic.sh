#!/bin/sh
# Diagnostic script for nwg-dock
# Logs dock status to debug.log

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
TIMESTAMP=$(date +%s)

# Function to log JSON
log_json() {
  echo "{\"id\":\"log_${TIMESTAMP}_$(date +%N)\",\"timestamp\":$(date +%s)000,\"location\":\"dock-diagnostic.sh:$1\",\"message\":\"$2\",\"data\":$3,\"sessionId\":\"sway-debug\",\"runId\":\"dock-check\",\"hypothesisId\":\"$4\"}" >> "$LOG_FILE"
}

# #region agent log - Hypothesis A: nwg-dock process check before start
DOCK_PID_BEFORE=$(pgrep -x nwg-dock || echo "none")
log_json "DOCK_PROCESS_BEFORE" "Checking nwg-dock process before start" "{\"pid\":\"$DOCK_PID_BEFORE\"}" "A"
# #endregion

# #region agent log - Hypothesis B: nwg-dock parameter validation
# NOTE: -r means "Leave the program resident, but w/o hotspot" - this DISABLES hover detection!
# NOTE: -w means "number of Workspaces" not width!
log_json "DOCK_PARAMS" "nwg-dock parameters being used" "{\"auto_hide\":\"-d\",\"resident_no_hotspot\":\"-r (DISABLES HOTSPOT)\",\"position\":\"bottom\",\"icon_size\":48,\"workspace_count\":5,\"margin_bottom\":10,\"hotspot_delay\":10}" "B"
# #endregion

# #region agent log - Hypothesis C: nwg-dock binary check
NWG_DOCK_PATH=$(which nwg-dock 2>/dev/null || echo "not_found")
NWG_DOCK_EXISTS=$(test -f "$NWG_DOCK_PATH" && echo "exists" || echo "not_found")
log_json "DOCK_BINARY_CHECK" "Checking nwg-dock binary" "{\"path\":\"$NWG_DOCK_PATH\",\"exists\":\"$NWG_DOCK_EXISTS\"}" "C"
# #endregion

# Start nwg-dock with error capture
# #region agent log - Hypothesis D: nwg-dock start attempt
nwg-dock -d -r -p bottom -i 48 -w 5 -mb 10 -hd 10 -c "rofi -show drun" 2>&1 &
DOCK_PID=$!
sleep 2
# #endregion

# #region agent log - Hypothesis E: nwg-dock process after start
DOCK_PID_AFTER=$(pgrep -x nwg-dock || echo "not_running")
DOCK_PS=$(ps aux | grep nwg-dock | grep -v grep || echo "not_found")
log_json "DOCK_PROCESS_AFTER" "Checking nwg-dock process after start" "{\"started_pid\":\"$DOCK_PID\",\"running_pid\":\"$DOCK_PID_AFTER\",\"ps_output\":\"$DOCK_PS\"}" "E"
# #endregion

# #region agent log - Hypothesis F: nwg-dock window check
sleep 1
SWAY_TREE=$(swaymsg -t get_tree 2>/dev/null || echo "swaymsg_failed")
DOCK_WINDOW=$(echo "$SWAY_TREE" | jq -r '.. | select(.app_id? == "nwg-dock") | {app_id,visible,rect,geometry}' 2>/dev/null || echo "no_window_or_jq_failed")
log_json "DOCK_WINDOW_CHECK" "Checking nwg-dock window in sway tree" "{\"window_info\":\"$DOCK_WINDOW\"}" "F"
# #endregion

# #region agent log - Hypothesis G: nwg-dock CSS check
CSS_FILE="$HOME/.config/nwg-dock/style.css"
if [ -f "$CSS_FILE" ]; then
  CSS_SIZE=$(stat -c%s "$CSS_FILE" 2>/dev/null || echo "0")
  CSS_OPACITY=$(grep -i "opacity\|background.*rgba" "$CSS_FILE" | head -3 || echo "no_opacity_found")
  log_json "DOCK_CSS_CHECK" "Checking nwg-dock CSS file" "{\"exists\":true,\"size\":\"$CSS_SIZE\",\"opacity_lines\":\"$CSS_OPACITY\"}" "G"
else
  log_json "DOCK_CSS_CHECK" "nwg-dock CSS file not found" "{\"path\":\"$CSS_FILE\",\"exists\":false}" "G"
fi
# #endregion

