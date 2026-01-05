#!/bin/sh
# Window movement script with conditional behavior
# Usage: window-move.sh <direction> (left|right|up|down)

DIRECTION=$1
# Get floating status - check if window is floating
FLOATING=$(swaymsg -t get_tree | jq -r '.. | select(.type? == "con" and .focused? == true) | if .floating == "user_on" or .floating == "auto_on" then "true" else "false" end')

if [ "$FLOATING" = "true" ]; then
    # Floating window: move by 5% using ppt (percentage points)
    swaymsg move "$DIRECTION" 5 ppt
else
    # Tiled window: move (swap) in direction
    swaymsg move "$DIRECTION"
fi

