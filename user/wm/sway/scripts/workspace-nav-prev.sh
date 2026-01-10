#!/usr/bin/env bash
# Navigate to previous workspace with auto-creation and wrapping (Option B)
# Usage: workspace-nav-prev.sh

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

# Get previous workspace (with wrapping)
TARGET_WS="$(get_prev_workspace_wrap "$CURRENT_WS" "${GROUP_WORKSPACES[@]}")"

# Focus the workspace (creates it if it doesn't exist)
focus_workspace "$TARGET_WS"

exit 0
