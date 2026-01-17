#!/usr/bin/env bash
# Wrapper script for pavucontrol that handles scratchpad windows correctly
# This script calls app-toggle.sh but adds special handling for scratchpad windows

APP_ID="org.pulseaudio.pavucontrol"
CMD="${1:-pavucontrol}"

# First, try to find existing pavucontrol windows
WINDOW_JSON=$(swaymsg -t get_tree 2>/dev/null | jq -r --arg app "$APP_ID" '
    [
        recurse(.nodes[]?, .floating_nodes[]?) 
        | select(.type=="con" or .type=="floating_con")
        | select(
            ((.app_id // "") | ascii_downcase == ($app | ascii_downcase)) or 
            ((.window_properties.class // "") | ascii_downcase == ($app | ascii_downcase))
        )
        | {id, focused, visible, scratchpad_state}
    ]
' 2>/dev/null)

# If no windows found, launch it using app-toggle.sh
if [ -z "$WINDOW_JSON" ] || [ "$WINDOW_JSON" = "[]" ]; then
    exec "$(dirname "$0")/app-toggle.sh" "$APP_ID" "$CMD"
    exit 0
fi

# Check if any window is focused
FOCUSED_ID=$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | select(.focused? == true) | .id' 2>/dev/null || echo "none")
ID_LIST=$(echo "$WINDOW_JSON" | jq -r '.[].id' 2>/dev/null || echo "")

# If focused window is pavucontrol, hide it
if echo "$ID_LIST" | grep -q "^$FOCUSED_ID$"; then
    # Hide to scratchpad
    swaymsg "move scratchpad" 2>/dev/null
    exit 0
fi

# Find a window that's in scratchpad (not visible)
SCRATCHPAD_ID=$(echo "$WINDOW_JSON" | jq -r '.[] | select(.visible != true) | .id' 2>/dev/null | head -n 1)

if [ -n "$SCRATCHPAD_ID" ] && [ "$SCRATCHPAD_ID" != "null" ]; then
    # Window is in scratchpad - bring it to current workspace
    swaymsg "[con_id=$SCRATCHPAD_ID] scratchpad show" 2>/dev/null
else
    # Window is visible but not focused - just focus it
    TARGET_ID=$(echo "$ID_LIST" | head -n 1)
    if [ -n "$TARGET_ID" ]; then
        swaymsg "[con_id=$TARGET_ID] focus" 2>/dev/null
    fi
fi
