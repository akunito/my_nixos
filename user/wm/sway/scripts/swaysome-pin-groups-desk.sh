#!/usr/bin/env bash
set -euo pipefail

# DESK-only: Pin output -> swaysome group mapping deterministically by hardware ID.
# Goal:
# - Samsung  -> group 1 (11-20)
# - NSL      -> group 2 (21-30)
# - Philips  -> group 3 (31-40)
# - BNQ      -> group 4 (41-50)

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
JQ_BIN="$(command -v jq 2>/dev/null || true)"
SWAYSOME_BIN="$(command -v swaysome 2>/dev/null || true)"

[ -n "$SWAYMSG_BIN" ] || exit 0
[ -n "$JQ_BIN" ] || exit 0
[ -n "$SWAYSOME_BIN" ] || exit 0

# Hardware IDs (exact matches from swaymsg -t get_outputs)
SAMSUNG="Samsung Electric Company Odyssey G70NC H1AK500000"
NSL="NSL RGB-27QHDS    Unknown"
PHILIPS="Philips Consumer Electronics Company PHILIPS FTV 0x01010101"
BNQ="BNQ ZOWIE XL LCD 7CK03588SL0"

echo "DESK: Starting hardware-ID-based workspace initialization..." >&2

# Function to get output name by hardware ID
get_output_by_hwid() {
  local hwid="$1"
  $SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r --arg hwid "$hwid" '
    .[] | select(.active==true) | select((.make + " " + .model + " " + .serial) == $hwid) | .name
  ' | head -n1
}

# Create initial workspace on each monitor using swaymsg
create_initial_workspace() {
  local hwid="$1"
  local workspace="$2"
  local name="$3"

  local output_name
  output_name="$(get_output_by_hwid "$hwid")"

  if [ -n "$output_name" ]; then
    echo "DESK: Creating workspace $workspace on $name ($hwid) via output $output_name" >&2
    # Focus output and create workspace
    $SWAYMSG_BIN "focus output \"$output_name\"" >/dev/null 2>&1
    $SWAYMSG_BIN "workspace number $workspace" >/dev/null 2>&1
    echo "DESK: Workspace $workspace created on $name" >&2
  else
    echo "DESK: WARNING - $name ($hwid) not found or not active" >&2
  fi
}

create_initial_workspace "$SAMSUNG" 11 "Samsung"
create_initial_workspace "$NSL" 21 "NSL"
create_initial_workspace "$PHILIPS" 31 "Philips"
create_initial_workspace "$BNQ" 41 "BNQ"

echo "DESK: Group pinning complete" >&2
exit 0


