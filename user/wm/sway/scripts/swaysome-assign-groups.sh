#!/usr/bin/env bash
set -euo pipefail

# Assign swaysome workspace groups to monitors based on config file.
# Config file: ~/.config/sway/workspace-groups.conf
#
# Format:
#   MONITOR_HARDWARE_ID=GROUP_NUMBER
#   *=auto  (enables auto-assignment for unknown monitors)
#
# If no config file exists, falls back to auto-assignment (group 1, 2, 3, etc.)
#
# This is intentionally generic (safe for non-DESK profiles).

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

CONFIG="$HOME/.config/sway/workspace-groups.conf"

SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
JQ_BIN="$(command -v jq 2>/dev/null || true)"
SWAYSOME_BIN="$(command -v swaysome 2>/dev/null || true)"

[ -n "$SWAYMSG_BIN" ] || exit 0
[ -n "$JQ_BIN" ] || exit 0
[ -n "$SWAYSOME_BIN" ] || exit 0

# Read config into associative array
declare -A GROUP_MAP
AUTO_ASSIGN=true  # Default to auto-assign if no config

if [[ -f "$CONFIG" ]]; then
    AUTO_ASSIGN=false  # Config exists, don't auto-assign unless explicitly enabled
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        # Trim whitespace
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$key" || "$key" == \#* ]] && continue

        if [[ "$key" == "*" && "$value" == "auto" ]]; then
            AUTO_ASSIGN=true
        else
            GROUP_MAP["$key"]="$value"
        fi
    done < "$CONFIG"
fi

# Get hardware ID for a monitor (make + model + serial)
get_hw_id() {
    local name="$1"
    $SWAYMSG_BIN -t get_outputs | $JQ_BIN -r \
        ".[] | select(.name==\"$name\") | \"\(.make // \"\") \(.model // \"\") \(.serial // \"\")\"" \
        | sed 's/  */ /g; s/^ *//; s/ *$//'
}

# Capture current focus so we can restore it after group assignment.
FOCUSED_OUTPUT="$($SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' | head -n1 || true)"
FOCUSED_WS="$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' | head -n1 || true)"

# Get active outputs
mapfile -t OUTPUTS < <(
    $SWAYMSG_BIN -t get_outputs 2>/dev/null \
        | $JQ_BIN -r '.[] | select(.active==true) | .name'
)

if [ "${#OUTPUTS[@]}" -eq 0 ]; then
    exit 0
fi

auto_group=1
for out in "${OUTPUTS[@]}"; do
    hw_id=$(get_hw_id "$out")

    # Look up group from config (try both hardware ID and connector name)
    group=""
    for key in "$hw_id" "$out"; do
        if [[ -n "${GROUP_MAP[$key]:-}" ]]; then
            group="${GROUP_MAP[$key]}"
            break
        fi
    done

    # Auto-assign if not configured
    if [[ -z "$group" ]]; then
        if $AUTO_ASSIGN; then
            group=$auto_group
            ((auto_group++))
        else
            # Skip this monitor if not configured and auto-assign is disabled
            continue
        fi
    fi

    # Apply group
    $SWAYMSG_BIN "focus output \"$out\"" >/dev/null 2>&1 || true
    $SWAYSOME_BIN "focus-group" "$group" >/dev/null 2>&1 || true
    # Create the initial workspace for this group (11, 21, 31, etc.)
    $SWAYSOME_BIN "focus 1" >/dev/null 2>&1 || true
done

# Restore focus.
if [ -n "$FOCUSED_OUTPUT" ]; then
    $SWAYMSG_BIN "focus output \"$FOCUSED_OUTPUT\"" >/dev/null 2>&1 || true
fi
if [ -n "$FOCUSED_WS" ]; then
    $SWAYMSG_BIN "workspace \"$FOCUSED_WS\"" >/dev/null 2>&1 || true
fi

exit 0
