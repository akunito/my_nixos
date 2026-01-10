#!/usr/bin/env bash
set -euo pipefail

# Assign swaysome workspace groups starting at 1 for all active outputs and create initial workspaces.
# Purpose: ensure group 0 is never used (so workspaces 1-10 are not assigned to any output).
# Creates workspace 11 on first output, 21 on second output, 31 on third output, etc.
#
# This is intentionally generic (safe for non-DESK profiles).

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
JQ_BIN="$(command -v jq 2>/dev/null || true)"
SWAYSOME_BIN="$(command -v swaysome 2>/dev/null || true)"

[ -n "$SWAYMSG_BIN" ] || exit 0
[ -n "$JQ_BIN" ] || exit 0
[ -n "$SWAYSOME_BIN" ] || exit 0

# Capture current focus so we can restore it after group assignment.
FOCUSED_OUTPUT="$($SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' | head -n1 || true)"
FOCUSED_WS="$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | select(.focused==true) | .name' | head -n1 || true)"

mapfile -t OUTPUTS < <(
  $SWAYMSG_BIN -t get_outputs 2>/dev/null \
    | $JQ_BIN -r '.[] | select(.active==true) | .name'
)

if [ "${#OUTPUTS[@]}" -eq 0 ]; then
  exit 0
fi

idx=1
for out in "${OUTPUTS[@]}"; do
  # Focus the output by connector name (stable within a session) and assign group idx.
  $SWAYMSG_BIN "focus output \"$out\"" >/dev/null 2>&1 || true
  $SWAYSOME_BIN "focus-group" "$idx" >/dev/null 2>&1 || true
  # Create the initial workspace for this group (11, 21, 31, etc.)
  $SWAYSOME_BIN "focus 1" >/dev/null 2>&1 || true
  idx=$((idx + 1))
done

# Restore focus.
if [ -n "$FOCUSED_OUTPUT" ]; then
  $SWAYMSG_BIN "focus output \"$FOCUSED_OUTPUT\"" >/dev/null 2>&1 || true
fi
if [ -n "$FOCUSED_WS" ]; then
  $SWAYMSG_BIN "workspace \"$FOCUSED_WS\"" >/dev/null 2>&1 || true
fi

exit 0


