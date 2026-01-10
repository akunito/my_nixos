#!/usr/bin/env bash
# Shared workspace utilities for navigation and moving
# Provides functions for workspace group management with wrapping

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

# Get next workspace with wrapping (Option B)
# Args: CURRENT_WS GROUP_WORKSPACES_ARRAY
# Returns: workspace number to focus/create
get_next_workspace_wrap() {
    local current_ws="$1"
    shift
    local group_workspaces=("$@")

    # Find next workspace in sequence
    local next_ws=""
    for ws in "${group_workspaces[@]}"; do
        if [ "$ws" -gt "$current_ws" ]; then
            next_ws="$ws"
            break
        fi
    done

    if [ -n "$next_ws" ]; then
        echo "$next_ws"
    else
        # No next workspace, wrap to beginning
        echo "${group_workspaces[0]}"
    fi
}

# Get previous workspace with wrapping (Option B)
# Args: CURRENT_WS GROUP_WORKSPACES_ARRAY
# Returns: workspace number to focus/create
get_prev_workspace_wrap() {
    local current_ws="$1"
    shift
    local group_workspaces=("$@")

    # Find previous workspace in sequence
    local prev_ws=""
    for ((i=${#group_workspaces[@]}-1; i>=0; i--)); do
        local ws="${group_workspaces[i]}"
        if [ "$ws" -lt "$current_ws" ]; then
            prev_ws="$ws"
            break
        fi
    done

    if [ -n "$prev_ws" ]; then
        echo "$prev_ws"
    else
        # No previous workspace, wrap to end
        echo "${group_workspaces[-1]}"
    fi
}

# Focus or create workspace
# Args: WORKSPACE_NUMBER
focus_workspace() {
    local workspace="$1"
    $SWAYMSG_BIN "workspace number $workspace" >/dev/null 2>&1
}

# Move container to workspace
# Args: WORKSPACE_NUMBER
move_to_workspace() {
    local workspace="$1"
    $SWAYMSG_BIN "move container to workspace number $workspace" >/dev/null 2>&1
}
