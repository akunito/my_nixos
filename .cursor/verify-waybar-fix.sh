#!/usr/bin/env bash
# Comprehensive Waybar configuration verification
LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"

log_json() {
    local location="$1"
    local message="$2"
    local data="$3"
    local hypothesis="$4"
    echo "{\"timestamp\":$(date +%s000),\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"$hypothesis\"}" >> "$LOG_FILE"
}

> "$LOG_FILE"

log_json "verify-waybar-fix.sh:start" "Starting comprehensive Waybar verification" "{}" "A"

# Check source file for unsupported properties
SOURCE_FILE="/home/akunito/.dotfiles/user/wm/sway/waybar.nix"
if grep -v "comment\|/\*\|CRITICAL" "$SOURCE_FILE" 2>/dev/null | grep -q "pointer-events"; then
    log_json "verify-waybar-fix.sh:source-pointer-events" "ERROR: pointer-events found in source file (not in comment)" "{}" "B"
else
    log_json "verify-waybar-fix.sh:source-pointer-events" "OK: No pointer-events property in source file" "{}" "B"
fi

if grep -qE "height:" "$SOURCE_FILE" 2>&1 | grep -v "min-height\|comment"; then
    log_json "verify-waybar-fix.sh:source-height" "ERROR: height property found in source file" "{}" "C"
else
    log_json "verify-waybar-fix.sh:source-height" "OK: No height property in source file (only min-height)" "{}" "C"
fi

if grep -qE "#[0-9a-fA-F]{8}" "$SOURCE_FILE" 2>/dev/null; then
    HEX8_COUNT=$(grep -cE "#[0-9a-fA-F]{8}" "$SOURCE_FILE")
    log_json "verify-waybar-fix.sh:source-hex8" "ERROR: 8-digit hex colors found in source" "{\"count\":\"$HEX8_COUNT\"}" "D"
else
    log_json "verify-waybar-fix.sh:source-hex8" "OK: No 8-digit hex colors in source (using rgba)" "{}" "D"
fi

# Check generated CSS file
CSS_FILE="$HOME/.config/waybar/style.css"
if [ ! -f "$CSS_FILE" ]; then
    log_json "verify-waybar-fix.sh:css-missing" "ERROR: CSS file does not exist" "{\"file\":\"$CSS_FILE\"}" "E"
else
    log_json "verify-waybar-fix.sh:css-exists" "OK: CSS file exists" "{\"file\":\"$CSS_FILE\"}" "E"
    
    if grep -q "pointer-events" "$CSS_FILE" 2>/dev/null; then
        POINTER_LINE=$(grep -n "pointer-events" "$CSS_FILE" | head -1)
        log_json "verify-waybar-fix.sh:css-pointer-events" "ERROR: pointer-events found in generated CSS (needs rebuild)" "{\"line\":\"$POINTER_LINE\"}" "F"
    else
        log_json "verify-waybar-fix.sh:css-pointer-events" "OK: No pointer-events in generated CSS" "{}" "F"
    fi
    
    if grep -qE "height:" "$CSS_FILE" 2>&1 | grep -v "min-height"; then
        HEIGHT_LINE=$(grep -nE "height:" "$CSS_FILE" | grep -v "min-height" | head -1)
        log_json "verify-waybar-fix.sh:css-height" "ERROR: height property found in generated CSS" "{\"line\":\"$HEIGHT_LINE\"}" "G"
    else
        log_json "verify-waybar-fix.sh:css-height" "OK: No height property in generated CSS" "{}" "G"
    fi
    
    if grep -qE "#[0-9a-fA-F]{8}" "$CSS_FILE" 2>/dev/null; then
        HEX8_LINES=$(grep -nE "#[0-9a-fA-F]{8}" "$CSS_FILE" | head -3)
        log_json "verify-waybar-fix.sh:css-hex8" "ERROR: 8-digit hex colors found in generated CSS" "{\"lines\":\"$HEX8_LINES\"}" "H"
    else
        RGBA_COUNT=$(grep -c "rgba(" "$CSS_FILE" || echo "0")
        log_json "verify-waybar-fix.sh:css-hex8" "OK: No 8-digit hex colors, using rgba()" "{\"rgbaCount\":\"$RGBA_COUNT\"}" "H"
    fi
fi

# Test Waybar parsing
WAYBAR_TEST=$(waybar -c ~/.config/waybar/config 2>&1 | head -10)
if echo "$WAYBAR_TEST" | grep -qi "error"; then
    ERRORS=$(echo "$WAYBAR_TEST" | grep -i "error")
    log_json "verify-waybar-fix.sh:waybar-errors" "ERROR: Waybar reports CSS errors" "{\"errors\":\"$ERRORS\"}" "I"
else
    log_json "verify-waybar-fix.sh:waybar-errors" "OK: Waybar parses CSS without errors" "{}" "I"
fi

# Check config structure
CONFIG_FILE="$HOME/.config/waybar/config"
if [ -f "$CONFIG_FILE" ]; then
    BAR_COUNT=$(cat "$CONFIG_FILE" | jq 'length' 2>/dev/null || echo "0")
    HAS_DOCK=$(cat "$CONFIG_FILE" | jq '.[] | select(.name == "dock")' 2>/dev/null | grep -q "dock" && echo "true" || echo "false")
    HAS_OUTPUT=$(cat "$CONFIG_FILE" | jq '.[0].output' 2>/dev/null | grep -q "DP-1" && echo "true" || echo "false")
    log_json "verify-waybar-fix.sh:config-structure" "Config structure check" "{\"barCount\":\"$BAR_COUNT\",\"hasDock\":\"$HAS_DOCK\",\"hasOutput\":\"$HAS_OUTPUT\"}" "J"
fi

log_json "verify-waybar-fix.sh:end" "Verification complete" "{}" "A"

echo "Verification complete. Check $LOG_FILE for details."

