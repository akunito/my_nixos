#!/bin/bash
# Debug script for Sway session startup
# This script will be called by SDDM to start Sway with full logging

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
SESSION_LOG="/home/akunito/.dotfiles/.cursor/sway-session.log"

# Function to log debug information
log_debug() {
    local message="$1"
    local data="$2"
    local timestamp=$(date +%s%3N)
    echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"debug-sway-startup.sh\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"sway-startup\",\"runId\":\"startup\"}" >> "$LOG_FILE"
}

# Log script start
log_debug "Sway startup script started" "{\"pid\":$$,\"user\":\"$USER\",\"home\":\"$HOME\"}"

# Log environment variables
log_debug "Environment check" "{\"PATH\":\"$PATH\",\"WAYLAND_DISPLAY\":\"$WAYLAND_DISPLAY\",\"XDG_SESSION_TYPE\":\"$XDG_SESSION_TYPE\",\"XDG_SESSION_DESKTOP\":\"$XDG_SESSION_DESKTOP\"}"

# Check if sway executable exists
SWAY_PATH=$(which sway 2>/dev/null)
if [ -z "$SWAY_PATH" ]; then
    log_debug "ERROR: sway not found in PATH" "{\"PATH\":\"$PATH\"}"
    exit 1
fi
log_debug "Sway executable found" "{\"path\":\"$SWAY_PATH\"}"

# Check if sway config exists
SWAY_CONFIG="$HOME/.config/sway/config"
if [ ! -f "$SWAY_CONFIG" ]; then
    log_debug "WARNING: Sway config not found" "{\"expected\":\"$SWAY_CONFIG\"}"
else
    log_debug "Sway config found" "{\"path\":\"$SWAY_CONFIG\",\"size\":$(stat -c%s "$SWAY_CONFIG" 2>/dev/null || echo 0)}"
fi

# Check systemd user services
log_debug "Systemd user services check" "{\"swayidle\":\"$(systemctl --user is-active swayidle.service 2>&1)\",\"clipman\":\"$(systemctl --user is-active clipman.service 2>&1)\"}"

# Check if we can access display
if [ -z "$WAYLAND_DISPLAY" ]; then
    log_debug "WARNING: WAYLAND_DISPLAY not set" "{}"
fi

# Try to validate sway config
if [ -f "$SWAY_CONFIG" ]; then
    SWAY_VALIDATE=$(swaymsg -t get_version 2>&1)
    log_debug "Sway validation attempt" "{\"result\":\"$SWAY_VALIDATE\"}"
fi

# Log before starting sway
log_debug "Starting Sway" "{\"command\":\"$SWAY_PATH\",\"config\":\"$SWAY_CONFIG\"}"

# Start Sway with full logging
exec "$SWAY_PATH" >> "$SESSION_LOG" 2>&1
EXIT_CODE=$?

# Log if we exit (shouldn't happen normally)
log_debug "Sway exited unexpectedly" "{\"exitCode\":$EXIT_CODE}"

exit $EXIT_CODE

