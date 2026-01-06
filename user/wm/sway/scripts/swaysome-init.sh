#!/bin/bash
# Initialize swaysome and assign workspace groups to monitors
# This script uses the "Wait, Then Assign" strategy to prevent race conditions

# 1. Initialize swaysome context
# This tells swaysome to start tracking workspaces.
swaysome init 1

# 2. THE FIX: Wait for monitors to wake up
# This sleep prevents the "race condition" where Sway commands 
# run before the monitors are actually ready.
# Without this, commands may fail or be sent to the wrong monitor
# (e.g., everything piling up on the first detected screen).
sleep 1

# Focus primary monitor first (ensures mouse cursor is positioned correctly)
swaymsg focus output DP-1

# 3. Initialize Monitor 1 (DP-1) -> Group 1 (Workspaces 1-10)
# Instead of trying to create "Workspace 1" manually (which might fail),
# we tell swaysome: "This monitor owns Group 1."
# Swaysome then automatically creates/focuses the correct workspaces.
swaysome focus-group 1

# 4. Initialize Monitor 2 (DP-2) -> Group 2 (Workspaces 11-20)
# We use 'focus-group 2' because swaysome groups are sequential blocks.
# Group 2 automatically contains the 11-20 range (includes our desired 11-15).
swaymsg focus output DP-2
swaysome focus-group 2

# 5. Initialize Optional Monitors (Check if they exist first)
# Monitor 3 (BenQ) -> Group 3 (Workspaces 21-30)
# This includes workspace 21 which we want for DP-3
# Note: Using simple "DP-3" grep (safer, less sensitive to JSON formatting)
if swaymsg -t get_outputs | grep -q "DP-3"; then
    swaymsg focus output DP-3
    swaysome focus-group 3
fi

# Monitor 4 (Philips) -> Group 4 (Workspaces 31-40)
# This includes workspace 31 which we want for HDMI-A-1
# Note: Using simple "HDMI-A-1" grep (safer, less sensitive to JSON formatting)
if swaymsg -t get_outputs | grep -q "HDMI-A-1"; then
    swaymsg focus output HDMI-A-1
    swaysome focus-group 4
fi

# 6. Final Polish: Return focus to your main screen
swaymsg focus output DP-1
swaysome focus 1

