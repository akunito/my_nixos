#!/bin/bash
# Test script to debug Sway startup issues
# Run this manually to see what happens when Sway tries to start

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"

log_debug() {
    local message="$1"
    local data="$2"
    local timestamp=$(date +%s%3N)
    echo "{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp},\"location\":\"test-sway-startup.sh\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"sway-debug\",\"runId\":\"manual-test\"}" >> "$LOG_FILE"
}

log_debug "=== Sway Startup Debug Test Started ===" "{\"user\":\"$USER\",\"home\":\"$HOME\"}"

# Check 1: Sway executable
SWAY_PATH=$(which sway)
if [ -z "$SWAY_PATH" ]; then
    log_debug "ERROR: sway not in PATH" "{\"PATH\":\"$PATH\"}"
    exit 1
fi
log_debug "Sway executable found" "{\"path\":\"$SWAY_PATH\",\"exists\":\"$(test -f \"$SWAY_PATH\" && echo true || echo false)\"}"

# Check 2: Config file
SWAY_CONFIG="$HOME/.config/sway/config"
if [ ! -f "$SWAY_CONFIG" ]; then
    log_debug "ERROR: Config file missing" "{\"expected\":\"$SWAY_CONFIG\"}"
    exit 1
fi
log_debug "Config file exists" "{\"path\":\"$SWAY_CONFIG\",\"size\":$(stat -c%s "$SWAY_CONFIG" 2>/dev/null || echo 0),\"readable\":\"$(test -r \"$SWAY_CONFIG\" && echo true || echo false)\"}"

# Check 3: Validate config syntax (if possible)
log_debug "Attempting config validation" "{\"method\":\"swaymsg -t get_version\"}"
SWAY_VERSION=$(swaymsg -t get_version 2>&1)
log_debug "Sway version check result" "{\"output\":\"$SWAY_VERSION\"}"

# Check 4: Check for required packages
log_debug "Checking required packages" "{\"swayfx\":\"$(which sway 2>&1)\",\"swaylock\":\"$(which swaylock 2>&1)\",\"waybar\":\"$(which waybar 2>&1)\"}"

# Check 5: Environment variables
log_debug "Environment check" "{\"WAYLAND_DISPLAY\":\"$WAYLAND_DISPLAY\",\"XDG_SESSION_TYPE\":\"$XDG_SESSION_TYPE\",\"XDG_RUNTIME_DIR\":\"$XDG_RUNTIME_DIR\",\"DISPLAY\":\"$DISPLAY\"}"

# Check 6: Test if we can access wayland socket
if [ -n "$XDG_RUNTIME_DIR" ]; then
    WAYLAND_SOCKETS=$(ls -la "$XDG_RUNTIME_DIR"/wayland* 2>/dev/null | wc -l)
    log_debug "Wayland sockets check" "{\"runtime_dir\":\"$XDG_RUNTIME_DIR\",\"socket_count\":$WAYLAND_SOCKETS}"
fi

# Check 7: Systemd user services status
log_debug "Systemd user services" "{\"swayidle\":\"$(systemctl --user is-active swayidle.service 2>&1)\",\"clipman\":\"$(systemctl --user is-active clipman.service 2>&1)\"}"

# Check 8: Try to start sway in test mode (dry run)
log_debug "Attempting dry-run config check" "{\"command\":\"sway -C $SWAY_CONFIG -d\"}"
SWAY_DRY_RUN=$(sway -C "$SWAY_CONFIG" -d 2>&1 | head -20)
log_debug "Sway dry-run result" "{\"output\":\"$SWAY_DRY_RUN\"}"

log_debug "=== Debug Test Complete ===" "{}"

