#!/bin/sh
# Initialize swaysome and assign workspace groups to monitors
# This script uses a "wait then assign" strategy and only configures outputs that are actually active.

set -eu

# Helper: true when an output exists AND is active (prevents phantom/off outputs receiving workspaces)
output_is_active() {
  name="$1"
  command -v jq >/dev/null 2>&1 || return 1
  swaymsg -t get_outputs 2>/dev/null | jq -e --arg name "$name" \
    '.[] | select(.name == $name and .active == true)' >/dev/null
}

# Wait briefly for Sway IPC to be ready and outputs to be enumerated.
i=0
while [ "$i" -lt 30 ]; do
  if swaymsg -t get_outputs >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

# 1. Initialize swaysome context
swaysome init 1

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
if output_is_active "DP-2"; then
  swaymsg focus output DP-2
  swaysome focus-group 2
fi

# 5. Initialize Optional Monitors (Check if they exist first)
# Monitor 3 (BenQ) -> Group 3 (Workspaces 21-30)
# This includes workspace 21 which we want for DP-3
# Note: Check for active output to avoid configuring disconnected/off outputs.
if output_is_active "DP-3"; then
  swaymsg focus output DP-3
  swaysome focus-group 3
fi

# Monitor 4 (Philips) -> Group 4 (Workspaces 31-40)
# This includes workspace 31 which we want for HDMI-A-1
# Note: Check for active output to avoid phantom workspace assignment when the panel is OFF.
if output_is_active "HDMI-A-1"; then
  swaymsg focus output HDMI-A-1
  swaysome focus-group 4
fi

# 6. Final Polish: Return focus to your main screen
swaymsg focus output DP-1
swaysome focus 1

