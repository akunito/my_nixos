#!/bin/sh
# Toggle SwayFX's default bar (swaybar) visibility
# This script toggles between hidden and visible states

# Check if bar is currently hidden
if swaymsg bar mode | grep -q "invisible\|hide"; then
    # Bar is hidden, show it
    swaymsg bar mode dock
    notify-send "Swaybar" "Bar enabled" -t 2000
else
    # Bar is visible, hide it
    swaymsg bar mode invisible
    notify-send "Swaybar" "Bar disabled" -t 2000
fi

