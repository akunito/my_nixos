#!/usr/bin/env bash
# Workspace Controller Script (Swaysome Replacement)
# Replicates swaysome workspace group mapping for Hyprland
# Usage: workspace-controller.sh <action> <index>
#   action: focus or move
#   index: 1-10 (workspace index within monitor group, where 10 represents key 0)

set -euo pipefail

ACTION="$1"
INDEX="$2"

# Validate arguments
if [[ ! "$ACTION" =~ ^(focus|move)$ ]]; then
    echo "Error: action must be 'focus' or 'move'" >&2
    exit 1
fi

if [[ ! "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ] || [ "$INDEX" -gt 10 ]; then
    echo "Error: index must be between 1 and 10" >&2
    exit 1
fi

# Get current Monitor ID (0, 1, 2...)
# jq returns the monitor ID as a number
MONITOR_ID=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .id')

if [ -z "$MONITOR_ID" ] || [ "$MONITOR_ID" == "null" ]; then
    echo "Error: Could not determine current monitor ID" >&2
    exit 1
fi

# Calculate offset: Monitor 0 = 0, Monitor 1 = 10, Monitor 2 = 20, etc.
OFFSET=$((MONITOR_ID * 10))

# Calculate target workspace: Offset + Index
# Monitor 0: Key 1 → Workspace 1, Key 2 → Workspace 2, ..., Key 0 → Workspace 10
# Monitor 1: Key 1 → Workspace 11, Key 2 → Workspace 12, ..., Key 0 → Workspace 20
# Monitor 2: Key 1 → Workspace 21, Key 2 → Workspace 22, ..., Key 0 → Workspace 30
TARGET=$((OFFSET + INDEX))

# Execute based on action
# CRITICAL: Use 'workspace' dispatcher, NOT 'focusworkspaceoncurrentmonitor'
# 'focusworkspaceoncurrentmonitor' steals workspaces from other monitors
if [ "$ACTION" == "focus" ]; then
    hyprctl dispatch workspace "$TARGET"
elif [ "$ACTION" == "move" ]; then
    hyprctl dispatch movetoworkspace "$TARGET"
fi

