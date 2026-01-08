#!/usr/bin/env bash
# Window Movement Script
# Conditional window movement (floating vs tiled)
# Usage: window-move.sh <direction>
#   direction: l (left), r (right), u (up), d (down)

set -euo pipefail

DIRECTION="$1"

# Validate direction
if [[ ! "$DIRECTION" =~ ^[lrud]$ ]]; then
    echo "Error: direction must be l, r, u, or d" >&2
    exit 1
fi

# Check if window is floating
# hyprctl activewindow returns JSON with 'floating' field (true/false)
IS_FLOATING=$(hyprctl activewindow -j | jq -r '.floating // false')

if [ "$IS_FLOATING" == "true" ]; then
    # Floating window: move by 5% of screen size
    # Get current monitor resolution
    MONITOR_INFO=$(hyprctl monitors -j | jq '.[] | select(.focused == true)')
    
    if [ -z "$MONITOR_INFO" ] || [ "$MONITOR_INFO" == "null" ]; then
        echo "Error: Could not determine current monitor resolution" >&2
        exit 1
    fi
    
    # Calculate 5% delta using jq math (round to integer)
    WIDTH=$(echo "$MONITOR_INFO" | jq -r '.width')
    HEIGHT=$(echo "$MONITOR_INFO" | jq -r '.height')
    
    # Calculate 5% of width and height, round to integer
    WIDTH_DELTA=$(echo "$MONITOR_INFO" | jq -r '(.width * 0.05) | floor')
    HEIGHT_DELTA=$(echo "$MONITOR_INFO" | jq -r '(.height * 0.05) | floor')
    
    # Map direction to pixel coordinates
    # Left: -X 0, Right: X 0, Up: 0 -Y, Down: 0 Y
    case "$DIRECTION" in
        l)
            X=$((WIDTH_DELTA * -1))
            Y=0
            ;;
        r)
            X=$WIDTH_DELTA
            Y=0
            ;;
        u)
            X=0
            Y=$((HEIGHT_DELTA * -1))
            ;;
        d)
            X=0
            Y=$HEIGHT_DELTA
            ;;
    esac
    
    # Execute movewindowpixel with calculated coordinates
    # Format: "x y" as single string argument
    hyprctl dispatch movewindowpixel "$X $Y"
else
    # Tiled window: swap position in direction
    # Hyprland uses: l, r, u, d for directions
    hyprctl dispatch movewindow "$DIRECTION"
fi

