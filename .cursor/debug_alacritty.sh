#!/usr/bin/env bash
# Debug script for Alacritty keybindings
# Log path: /home/akunito/.dotfiles/.cursor/debug.log

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
ALACRITTY_CONFIG="${HOME}/.config/alacritty/alacritty.yml"

log_entry() {
    local hypothesis_id=$1
    local message=$2
    local data=$3
    local timestamp=$(date +%s%3N)
    local location="debug_alacritty.sh:${BASH_LINENO[0]}"
    
    echo "{\"id\":\"log_${timestamp}_$(openssl rand -hex 3)\",\"timestamp\":${timestamp},\"location\":\"${location}\",\"message\":\"${message}\",\"data\":${data},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"${hypothesis_id}\"}" >> "$LOG_FILE"
}

# #region agent log
log_entry "A" "Script started" "{\"config_path\":\"${ALACRITTY_CONFIG}\"}"
# #endregion

# Check if config file exists
if [ ! -f "$ALACRITTY_CONFIG" ]; then
    # #region agent log
    log_entry "C" "Config file missing" "{\"path\":\"${ALACRITTY_CONFIG}\"}"
    # #endregion
    echo "ERROR: Alacritty config file not found at $ALACRITTY_CONFIG"
    exit 1
fi

# #region agent log
log_entry "A" "Config file exists" "{\"path\":\"${ALACRITTY_CONFIG}\",\"size\":$(stat -f%z "$ALACRITTY_CONFIG" 2>/dev/null || stat -c%s "$ALACRITTY_CONFIG" 2>/dev/null || echo 0)}"
# #endregion

# Extract key_bindings section
KEYBINDINGS_SECTION=$(grep -A 100 "^key_bindings:" "$ALACRITTY_CONFIG" | head -20)

# #region agent log
log_entry "A" "Keybindings section extracted" "{\"lines\":$(echo "$KEYBINDINGS_SECTION" | wc -l),\"preview\":\"$(echo "$KEYBINDINGS_SECTION" | head -5 | tr '\n' ';')\"}"
# #endregion

# Check for our specific keybindings
echo "=== Checking for Ctrl+C keybinding ==="
CTRL_C=$(grep -E "key:.*C.*mods:.*Control" "$ALACRITTY_CONFIG" | grep -v "Shift")
# #region agent log
log_entry "B" "Ctrl+C binding check" "{\"found\":$(echo "$CTRL_C" | wc -l),\"content\":\"$(echo "$CTRL_C" | head -1)\"}"
# #endregion
echo "$CTRL_C"

echo "=== Checking for Ctrl+V keybinding ==="
CTRL_V=$(grep -E "key:.*V.*mods:.*Control" "$ALACRITTY_CONFIG" | grep -v "Shift")
# #region agent log
log_entry "B" "Ctrl+V binding check" "{\"found\":$(echo "$CTRL_V" | wc -l),\"content\":\"$(echo "$CTRL_V" | head -1)\"}"
# #endregion
echo "$CTRL_V"

echo "=== Checking for Ctrl+X keybinding ==="
CTRL_X=$(grep -E "key:.*X.*mods:.*Control" "$ALACRITTY_CONFIG" | grep -v "Shift")
# #region agent log
log_entry "B" "Ctrl+X binding check" "{\"found\":$(echo "$CTRL_X" | wc -l),\"content\":\"$(echo "$CTRL_X" | head -1)\"}"
# #endregion
echo "$CTRL_X"

# Check action types
echo "=== Checking action types ==="
ACTIONS=$(grep -E "action:" "$ALACRITTY_CONFIG" | head -10)
# #region agent log
log_entry "D" "Action types found" "{\"count\":$(echo "$ACTIONS" | wc -l),\"actions\":\"$(echo "$ACTIONS" | tr '\n' ';')\"}"
# #endregion
echo "$ACTIONS"

# Check for Copy vs CopySelection
echo "=== Checking for Copy action ==="
COPY_ACTION=$(grep -E "action:.*Copy" "$ALACRITTY_CONFIG")
# #region agent log
log_entry "A" "Copy action check" "{\"found\":$(echo "$COPY_ACTION" | wc -l),\"content\":\"$(echo "$COPY_ACTION" | head -3 | tr '\n' ';')\"}"
# #endregion
echo "$COPY_ACTION"

# Check for Paste action
echo "=== Checking for Paste action ==="
PASTE_ACTION=$(grep -E "action:.*Paste" "$ALACRITTY_CONFIG")
# #region agent log
log_entry "A" "Paste action check" "{\"found\":$(echo "$PASTE_ACTION" | wc -l),\"content\":\"$(echo "$PASTE_ACTION" | head -3 | tr '\n' ';')\"}"
# #endregion
echo "$PASTE_ACTION"

# Check for Ctrl+Shift+C (SIGINT)
echo "=== Checking for Ctrl+Shift+C (SIGINT) ==="
CTRL_SHIFT_C=$(grep -E "key:.*C.*mods:.*Control.*Shift" "$ALACRITTY_CONFIG" || grep -E "key:.*C.*mods:.*Shift.*Control" "$ALACRITTY_CONFIG")
# #region agent log
log_entry "B" "Ctrl+Shift+C binding check" "{\"found\":$(echo "$CTRL_SHIFT_C" | wc -l),\"content\":\"$(echo "$CTRL_SHIFT_C" | head -1)\"}"
# #endregion
echo "$CTRL_SHIFT_C"

# Check modifier syntax
echo "=== Checking modifier syntax ==="
MODS_SYNTAX=$(grep -E "mods:" "$ALACRITTY_CONFIG" | head -5)
# #region agent log
log_entry "E" "Modifier syntax check" "{\"examples\":\"$(echo "$MODS_SYNTAX" | tr '\n' ';')\"}"
# #endregion
echo "$MODS_SYNTAX"

# Check if there are conflicting default bindings
echo "=== Checking for default bindings that might conflict ==="
DEFAULT_BINDINGS=$(grep -E "key:.*C|key:.*V|key:.*X" "$ALACRITTY_CONFIG" | grep -v "#")
# #region agent log
log_entry "B" "All C/V/X bindings" "{\"count\":$(echo "$DEFAULT_BINDINGS" | wc -l),\"bindings\":\"$(echo "$DEFAULT_BINDINGS" | head -10 | tr '\n' ';')\"}"
# #endregion
echo "$DEFAULT_BINDINGS"

# #region agent log
log_entry "A" "Script completed" "{}"
# #endregion

echo ""
echo "=== Full key_bindings section (first 30 lines) ==="
grep -A 30 "^key_bindings:" "$ALACRITTY_CONFIG" | head -30

