#!/bin/bash
# Debug script to verify Waybar CSS and config
LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"

log_json() {
    local location="$1"
    local message="$2"
    local data="$3"
    local hypothesis="$4"
    echo "{\"timestamp\":$(date +%s000),\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"$hypothesis\"}" >> "$LOG_FILE"
}

> "$LOG_FILE"

log_json "debug-waybar-css.sh:start" "Starting Waybar CSS verification" "{}" "A"

# Check CSS file for height property errors
if grep -q "height:" ~/.config/waybar/style.css; then
    HEIGHT_LINES=$(grep -n "height:" ~/.config/waybar/style.css | grep -v "min-height" | head -5)
    log_json "debug-waybar-css.sh:height-found" "Found 'height:' property (may cause errors)" "{\"lines\":\"$HEIGHT_LINES\"}" "B"
else
    log_json "debug-waybar-css.sh:height-not-found" "No 'height:' property found (good)" "{}" "B"
fi

# Check for 8-digit hex colors
if grep -qE "#[0-9a-fA-F]{8}" ~/.config/waybar/style.css; then
    HEX8_COUNT=$(grep -cE "#[0-9a-fA-F]{8}" ~/.config/waybar/style.css)
    log_json "debug-waybar-css.sh:hex8-found" "Found 8-digit hex colors (error)" "{\"count\":\"$HEX8_COUNT\"}" "C"
else
    log_json "debug-waybar-css.sh:hex8-not-found" "No 8-digit hex colors found (good)" "{}" "C"
fi

# Check for rgba() format
RGBA_COUNT=$(grep -c "rgba(" ~/.config/waybar/style.css || echo "0")
log_json "debug-waybar-css.sh:rgba-count" "rgba() format usage" "{\"count\":\"$RGBA_COUNT\"}" "D"

# Test Waybar CSS parsing
WAYBAR_TEST=$(waybar -c ~/.config/waybar/config 2>&1 | head -5)
log_json "debug-waybar-css.sh:waybar-test" "Waybar CSS test output" "{\"output\":\"$WAYBAR_TEST\"}" "E"

# Check dock CSS
if grep -q "window#waybar.dock" ~/.config/waybar/style.css; then
    DOCK_CSS=$(grep -A 10 "window#waybar.dock" ~/.config/waybar/style.css | head -12)
    log_json "debug-waybar-css.sh:dock-css-found" "Dock CSS found" "{\"css\":\"$DOCK_CSS\"}" "F"
else
    log_json "debug-waybar-css.sh:dock-css-missing" "Dock CSS NOT found" "{}" "F"
fi

log_json "debug-waybar-css.sh:end" "Verification complete" "{}" "A"

echo "Debug info written to $LOG_FILE"

