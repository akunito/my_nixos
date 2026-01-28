#!/bin/bash
# Debug script to verify Waybar configuration
# This checks the generated config file and system state

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
CONFIG_FILE="${HOME}/.config/waybar/config"

# Function to log JSON
log_json() {
    local location="$1"
    local message="$2"
    local data="$3"
    local hypothesis="$4"
    echo "{\"timestamp\":$(date +%s000),\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"$hypothesis\"}" >> "$LOG_FILE"
}

# Clear previous logs
> "$LOG_FILE"

log_json "debug-waybar-config.sh:start" "Starting Waybar config verification" "{}" "A"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_json "debug-waybar-config.sh:config-missing" "Config file does not exist" "{\"configFile\":\"$CONFIG_FILE\"}" "A"
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

log_json "debug-waybar-config.sh:config-exists" "Config file exists" "{\"configFile\":\"$CONFIG_FILE\"}" "A"

# Check if config has primary monitor output field
if grep -q '"output"' "$CONFIG_FILE"; then
    OUTPUT_VALUE=$(grep -A 1 '"output"' "$CONFIG_FILE" | head -2 | grep -o '"[^"]*"' | head -1 | tr -d '"')
    log_json "debug-waybar-config.sh:output-found" "Output field found in config" "{\"outputValue\":\"$OUTPUT_VALUE\"}" "B"
else
    log_json "debug-waybar-config.sh:output-missing" "Output field NOT found in config" "{}" "B"
fi

# Check if config has dock bar with name="dock"
if grep -q '"name".*"dock"' "$CONFIG_FILE" || grep -q '"name":\s*"dock"' "$CONFIG_FILE"; then
    log_json "debug-waybar-config.sh:dock-name-found" "Dock bar with name=dock found" "{}" "C"
else
    log_json "debug-waybar-config.sh:dock-name-missing" "Dock bar name=dock NOT found" "{}" "C"
fi

# Check if workspaces have all-outputs = true
if grep -q '"all-outputs".*true' "$CONFIG_FILE"; then
    log_json "debug-waybar-config.sh:all-outputs-true" "all-outputs = true found" "{}" "D"
else
    log_json "debug-waybar-config.sh:all-outputs-false" "all-outputs = true NOT found (may be false or missing)" "{}" "D"
fi

# Check number of bar configurations
BAR_COUNT=$(grep -c '"layer".*"top"' "$CONFIG_FILE" || echo "0")
log_json "debug-waybar-config.sh:bar-count" "Number of top bars found" "{\"barCount\":\"$BAR_COUNT\"}" "E"

# Check if waybar process is running
if pgrep -f "waybar.*-c" > /dev/null; then
    WAYBAR_PID=$(pgrep -f "waybar.*-c" | head -1)
    WAYBAR_CMD=$(ps -p "$WAYBAR_PID" -o cmd= 2>/dev/null || echo "unknown")
    log_json "debug-waybar-config.sh:waybar-running" "Waybar process is running" "{\"pid\":\"$WAYBAR_PID\",\"cmd\":\"$WAYBAR_CMD\"}" "F"
else
    log_json "debug-waybar-config.sh:waybar-not-running" "Waybar process NOT running" "{}" "F"
fi

# Check config file modification time
CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)
AGE_SECONDS=$((CURRENT_TIME - CONFIG_MTIME))
log_json "debug-waybar-config.sh:config-age" "Config file age" "{\"ageSeconds\":\"$AGE_SECONDS\",\"mtime\":\"$CONFIG_MTIME\"}" "G"

log_json "debug-waybar-config.sh:end" "Verification complete" "{}" "A"

echo "Debug information written to $LOG_FILE"
echo "Config file: $CONFIG_FILE"
echo "Config age: $AGE_SECONDS seconds"

