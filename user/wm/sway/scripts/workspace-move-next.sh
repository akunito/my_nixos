#!/usr/bin/env bash
# Move container to next workspace with auto-creation and wrapping (Option B)
# Usage: workspace-move-next.sh

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/workspace-utils.sh"

# Get current workspace info
read -r CURRENT_WS CURRENT_OUTPUT GROUP_NUM <<< "$(get_current_workspace_info)"

# Get all workspaces in current group
mapfile -t GROUP_WORKSPACES < <(get_group_workspaces "$GROUP_NUM" "$CURRENT_OUTPUT")

if [ ${#GROUP_WORKSPACES[@]} -eq 0 ]; then
    echo "ERROR: No workspaces found in group $GROUP_NUM" >&2
    exit 1
fi

# Get next workspace (with wrapping)
TARGET_WS="$(get_next_workspace_wrap "$CURRENT_WS" "${GROUP_WORKSPACES[@]}")"

# Move container to the workspace (creates it if it doesn't exist)
move_to_workspace "$TARGET_WS"

exit 0
