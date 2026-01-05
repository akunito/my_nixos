#!/bin/sh
# Smart screenshot workflow for SwayFX
# Usage: screenshot.sh [full|area]
#
# full: Captures the currently focused monitor (auto-detects)
# area: Allows selecting a region with slurp

set -e  # Exit on error

MODE="${1:-area}"

if [ "$MODE" = "full" ]; then
    # Detect currently focused output
    FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused == true) | .name')
    
    if [ -z "$FOCUSED_OUTPUT" ]; then
        # Fallback: use first output if no focused output found
        FOCUSED_OUTPUT=$(swaymsg -t get_outputs | jq -r '.[0].name')
    fi
    
    # Capture full monitor and open in swappy
    grim -o "$FOCUSED_OUTPUT" - | swappy -f - | wl-copy
elif [ "$MODE" = "area" ]; then
    # Select area and capture, then open in swappy
    grim -g "$(slurp)" - | swappy -f - | wl-copy
else
    echo "Usage: screenshot.sh [full|area]"
    exit 1
fi

