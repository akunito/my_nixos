#!/usr/bin/env bash
# Comprehensive startup logging for workspace assignment debugging

STARTUP_LOG="/tmp/sway-workspace-startup.log"
WORKSPACE_LOG="/tmp/sway-workspace-assignment.log"

# Function to log with timestamp
log_event() {
    echo "=== $1 ===" >> "$STARTUP_LOG"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S.%3N')" >> "$STARTUP_LOG"
    echo "PID: $$" >> "$STARTUP_LOG"
    echo "$2" >> "$STARTUP_LOG"
}

# Log sway startup
log_event "SWAY SESSION START" "Sway session starting"

# Wait a bit for sway to initialize
sleep 1

# Log initial monitor state
log_event "INITIAL MONITOR STATE" "Monitors at sway startup"
swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.active==true) | "\(.name): \(.make) \(.model) \(.serial) -> \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz, scale: \(.scale)"' >> "$STARTUP_LOG" 2>&1 || echo "Failed to get monitor state" >> "$STARTUP_LOG"

# Log initial workspace state
log_event "INITIAL WORKSPACE STATE" "Workspaces at sway startup"
swaymsg -t get_workspaces 2>/dev/null | jq -r '.[] | "Workspace \(.name) -> \(.output) (focused: \(.focused))"' >> "$STARTUP_LOG" 2>&1 || echo "Failed to get workspace state" >> "$STARTUP_LOG"

# Monitor for kanshi startup
log_event "WAITING FOR KANSHI" "Monitoring for kanshi service startup"
for i in {1..30}; do
    if systemctl --user is-active kanshi.service >/dev/null 2>&1; then
        log_event "KANSHI STARTED" "Kanshi service is now active (attempt $i)"
        # Log monitor state after kanshi
        swaymsg -t get_outputs 2>/dev/null | jq -r '.[] | select(.active==true) | "POST-KANSHI \(.name): \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz, scale: \(.scale)"' >> "$STARTUP_LOG" 2>&1
        break
    fi
    sleep 0.1
done

# Monitor for workspace assignment script execution
log_event "WAITING FOR WORKSPACE ASSIGNMENT" "Monitoring for workspace assignment script execution"
for i in {1..50}; do
    if [ -f "$WORKSPACE_LOG" ] && [ $(grep -c "DESK WORKSPACE ASSIGNMENT START" "$WORKSPACE_LOG" 2>/dev/null || echo 0) -gt 0 ]; then
        log_event "WORKSPACE ASSIGNMENT STARTED" "Workspace assignment script started (attempt $i)"
        # Wait for it to complete
        sleep 2
        log_event "WORKSPACE ASSIGNMENT COMPLETE" "Checking final workspace state"
        swaymsg -t get_workspaces 2>/dev/null | jq -r '.[] | "FINAL Workspace \(.name) -> \(.output) (focused: \(.focused))"' >> "$STARTUP_LOG" 2>&1
        break
    fi
    sleep 0.1
done

# Monitor for startup apps
log_event "STARTUP APPS PHASE" "Startup applications phase beginning"
# This would be triggered by the startup apps script

log_event "STARTUP SEQUENCE COMPLETE" "Full startup logging complete"
