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

# Assign workspace range to output by hardware ID
assign_workspace_range_to_output() {
  local hwid="$1"
  local start_ws="$2"
  local end_ws="$3"
  local name="$4"

  local output_name
  output_name="$(get_output_by_hwid "$hwid")"

  if [ -n "$output_name" ]; then
    echo "DESK: Assigning $name ($hwid) workspaces $start_ws-$end_ws to $output_name" >&2

    # Focus the output first
    $SWAYMSG_BIN "focus output \"$output_name\"" >/dev/null 2>&1

    # Create the first workspace in the range on this output
    $SWAYMSG_BIN "workspace $start_ws" >/dev/null 2>&1

    echo "DESK: Successfully assigned $name workspaces $start_ws-$end_ws" >&2
  else
    echo "DESK: WARNING - $name ($hwid) not found or not active" >&2
  fi
}

# Assign workspace ranges deterministically by hardware ID
assign_workspace_range_to_output "$SAMSUNG" 11 20 "Samsung"
assign_workspace_range_to_output "$NSL" 21 30 "NSL"
assign_workspace_range_to_output "$PHILIPS" 31 40 "Philips"
assign_workspace_range_to_output "$BNQ" 41 50 "BNQ"

# Handle orphaned workspaces (workspaces 1-10 should go to the first monitor)
echo "DESK: Moving orphaned workspaces (1-10) to primary monitor..." >&2
for ws in 1 2 3 4 5 6 7 8 9 10; do
  if swaymsg -t get_workspaces | jq -r ".[] | select(.name==\"$ws\") | .output" | grep -v "DP-1" >/dev/null 2>&1; then
    $SWAYMSG_BIN "workspace $ws" >/dev/null 2>&1
    $SWAYMSG_BIN "move workspace to DP-1" >/dev/null 2>&1
  fi
done

echo "DESK: Hardware-ID-based workspace assignment complete" >&2
exit 0


