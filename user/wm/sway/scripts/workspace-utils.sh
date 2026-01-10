#!/usr/bin/env bash
# Shared workspace utilities for navigation and moving
# Provides functions for workspace group management with wrapping within group boundaries

set -euo pipefail

# Initialize PATH for Sway tools
PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
JQ_BIN="$(command -v jq 2>/dev/null || true)"

[ -n "$SWAYMSG_BIN" ] || exit 1
[ -n "$JQ_BIN" ] || exit 1

# Get current workspace information
# Returns: CURRENT_WS CURRENT_OUTPUT GROUP_NUM
get_current_workspace_info() {
    local current_ws current_output group_num

    current_ws="$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' | head -n1)"
    current_output="$($SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' | head -n1)"

    if [ -z "$current_ws" ] || [ -z "$current_output" ]; then
        echo "ERROR: Cannot determine current workspace/output" >&2
        exit 1
    fi

    # Extract group number (first digit for swaysome groups)
    group_num="${current_ws:0:1}"

    echo "$current_ws" "$current_output" "$group_num"
}

# Get all workspaces in the current group on current output
# Args: GROUP_NUM CURRENT_OUTPUT
# Returns: sorted list of workspace numbers
get_group_workspaces() {
    local group_num="$1"
    local current_output="$2"

    $SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r \
        --arg output "$current_output" \
        --arg group "$group_num" \
        '.[] | select(.output == $output) | select(.name | startswith($group)) | .name' | \
        sort -n
}

# Get next workspace with sequential creation and wrapping
# Args: CURRENT_WS GROUP_WORKSPACES_ARRAY
# Returns: workspace number to focus/create
get_next_workspace_wrap() {
    local current_ws="$1"
    shift
    local group_workspaces=("$@")

    # Calculate group boundaries (11-20 = group 1, 21-30 = group 2, etc.)
    local ws_num=$((current_ws))
    local group_num=$(((ws_num - 1) / 10))
    local group_start=$((group_num * 10 + 1))
    local group_end=$((group_num * 10 + 10))

    # Calculate next sequential workspace
    local next_sequential=$((current_ws + 1))

    # If beyond group end, wrap to group start
    if [ "$next_sequential" -gt "$group_end" ]; then
        echo "$group_start"
    else
        echo "$next_sequential"
    fi
}

# Get previous workspace with sequential creation and wrapping
# Args: CURRENT_WS GROUP_WORKSPACES_ARRAY
# Returns: workspace number to focus/create
get_prev_workspace_wrap() {
    local current_ws="$1"
    shift
    local group_workspaces=("$@")

    # Calculate group boundaries (11-20 = group 1, 21-30 = group 2, etc.)
    local ws_num=$((current_ws))
    local group_num=$(((ws_num - 1) / 10))
    local group_start=$((group_num * 10 + 1))
    local group_end=$((group_num * 10 + 10))

    # Calculate previous sequential workspace
    local prev_sequential=$((current_ws - 1))

    # If below group start, wrap to group end
    if [ "$prev_sequential" -lt "$group_start" ]; then
        echo "$group_end"
    else
        echo "$prev_sequential"
    fi
}

# Focus or create workspace
# Args: WORKSPACE_NUMBER OUTPUT_NAME
focus_workspace() {
    local workspace="$1"
    local output="$2"
    # Create/focus the workspace (output should already be focused)
    $SWAYMSG_BIN "workspace $workspace" >/dev/null 2>&1
}

# Move container to workspace
# Args: WORKSPACE_NUMBER OUTPUT_NAME
move_to_workspace() {
    local workspace="$1"
    local output="$2"
    # First focus the correct output, then move to workspace
    $SWAYMSG_BIN "focus output \"$output\"" >/dev/null 2>&1
    $SWAYMSG_BIN "move container to workspace $workspace" >/dev/null 2>&1
}
