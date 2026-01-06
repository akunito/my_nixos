#!/bin/bash
# Initialize swaysome and assign workspace groups to monitors

# Initialize swaysome FIRST (creates workspace groups as sequential blocks)
# Group 1 = Workspaces 1-10, Group 2 = Workspaces 11-20, etc.
swaysome init 1

# Wait for outputs to be ready
sleep 1

# Assign workspace group 1 to DP-1 (gives it workspaces 1-10)
swaymsg focus output DP-1
swaysome focus-group 1

# Assign workspace group 2 to DP-2 (gives it workspaces 11-20)
# This ensures DP-2 gets the 11-20 range, which includes our desired 11-15
swaymsg focus output DP-2
swaysome focus-group 2

# Assign workspace group 3 to DP-3 if enabled (gives it workspaces 21-30)
# This includes workspace 21 which we want for DP-3
if swaymsg -t get_outputs | grep -q '"name": "DP-3"'; then
    swaymsg focus output DP-3
    swaysome focus-group 3
fi

# Assign workspace group 4 to HDMI-A-1 if enabled (gives it workspaces 31-40)
# This includes workspace 31 which we want for HDMI-A-1
if swaymsg -t get_outputs | grep -q '"name": "HDMI-A-1"'; then
    swaymsg focus output HDMI-A-1
    swaysome focus-group 4
fi

# Return to workspace 1 on DP-1
swaymsg focus output DP-1
swaysome focus 1

