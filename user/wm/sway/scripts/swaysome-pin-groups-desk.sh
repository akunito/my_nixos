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

# Instrumentation: Log execution context and timing
LOG_FILE="/tmp/sway-workspace-assignment.log"
echo "=== DESK WORKSPACE ASSIGNMENT START ===" >> "$LOG_FILE"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "PID: $$" >> "$LOG_FILE"
echo "Called from: ${0}" >> "$LOG_FILE"
echo "Arguments: $*" >> "$LOG_FILE"

# Log current workspace state before any changes
echo "=== PRE-ASSIGNMENT STATE ===" >> "$LOG_FILE"
$SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | "Workspace \(.name) -> \(.output) (focused: \(.focused))"' >> "$LOG_FILE" 2>&1 || echo "Failed to get workspace state" >> "$LOG_FILE"

# Log monitor state
echo "=== MONITOR STATE ===" >> "$LOG_FILE"
$SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r '.[] | select(.active==true) | "\(.name): \(.make) \(.model) \(.serial) -> \(.current_mode.width)x\(.current_mode.height)@\(.current_mode.refresh/1000)Hz"' >> "$LOG_FILE" 2>&1 || echo "Failed to get monitor state" >> "$LOG_FILE"

echo "DESK: Starting hardware-ID-based workspace initialization..." >&2
echo "DESK: Starting hardware-ID-based workspace initialization..." >> "$LOG_FILE"

# Function to get output name by hardware ID
get_output_by_hwid() {
  local hwid="$1"
  local result
  result=$($SWAYMSG_BIN -t get_outputs 2>/dev/null | $JQ_BIN -r --arg hwid "$hwid" '
    .[] | select(.active==true) | select((.make + " " + .model + " " + .serial) == $hwid) | .name
  ' | head -n1)
  echo "Hardware ID lookup: '$hwid' -> '$result'" >> "$LOG_FILE"
  echo "$result"
}

# Assign workspace range to output by hardware ID
assign_workspace_range_to_output() {
  local hwid="$1"
  local start_ws="$2"
  local end_ws="$3"
  local name="$4"

  local output_name
  output_name="$(get_output_by_hwid "$hwid")"

  echo "=== ASSIGNING $name ($start_ws-$end_ws) ===" >> "$LOG_FILE"
  echo "Hardware ID: $hwid" >> "$LOG_FILE"
  echo "Target output: $output_name" >> "$LOG_FILE"

  if [ -n "$output_name" ]; then
    echo "DESK: Assigning $name ($hwid) workspaces $start_ws-$end_ws to $output_name" >&2
    echo "DESK: Assigning $name ($hwid) workspaces $start_ws-$end_ws to $output_name" >> "$LOG_FILE"

    # Move ALL existing workspaces in this range to the correct output
    moved_count=0
    for ws in $(seq "$start_ws" "$end_ws"); do
      local current_output
      current_output=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r ".[] | select(.name==\"$ws\") | .output" 2>/dev/null || echo "")
      if [ -n "$current_output" ] && [ "$current_output" != "$output_name" ]; then
        echo "Moving workspace $ws from $current_output to $output_name" >> "$LOG_FILE"
        echo "DESK: Moving workspace $ws to $output_name" >&2
        $SWAYMSG_BIN "workspace $ws" >/dev/null 2>&1
        $SWAYMSG_BIN "move workspace to \"$output_name\"" >/dev/null 2>&1
        moved_count=$((moved_count + 1))
      elif [ -n "$current_output" ]; then
        echo "Workspace $ws already on correct output $output_name" >> "$LOG_FILE"
      else
        echo "Workspace $ws does not exist yet" >> "$LOG_FILE"
      fi
    done
    echo "Moved $moved_count workspaces for $name" >> "$LOG_FILE"

    # Focus the output and create the first workspace if it doesn't exist
    echo "Focusing output $output_name and ensuring workspace $start_ws exists" >> "$LOG_FILE"
    $SWAYMSG_BIN "focus output \"$output_name\"" >/dev/null 2>&1
    $SWAYMSG_BIN "workspace $start_ws" >/dev/null 2>&1

    echo "DESK: Successfully assigned $name workspaces $start_ws-$end_ws" >&2
    echo "Successfully assigned $name workspaces $start_ws-$end_ws" >> "$LOG_FILE"
  else
    echo "DESK: WARNING - $name ($hwid) not found or not active" >&2
    echo "WARNING - $name ($hwid) not found or not active" >> "$LOG_FILE"
  fi
}

# Assign workspace ranges deterministically by hardware ID
assign_workspace_range_to_output "$SAMSUNG" 11 20 "Samsung"
assign_workspace_range_to_output "$NSL" 21 30 "NSL"
assign_workspace_range_to_output "$PHILIPS" 31 40 "Philips"
assign_workspace_range_to_output "$BNQ" 41 50 "BNQ"

# Renumber workspaces that are outside their monitor's assigned ranges
echo "=== RENUMBERING INVALID WORKSPACES ===" >> "$LOG_FILE"
echo "DESK: Renumbering workspaces outside correct ranges..." >&2
echo "Renumbering workspaces to fit monitor ranges" >> "$LOG_FILE"

renumbered_count=0

# Get workspace list and process each one
workspace_list=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | .name' 2>/dev/null || echo "")

for ws in $workspace_list; do
  if [ -n "$ws" ]; then
    # Get the output for this workspace
    output=$($SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r ".[] | select(.name==\"$ws\") | .output" 2>/dev/null || echo "")

    if [ -n "$output" ]; then
      # Determine if workspace is in the correct range for its monitor
      should_renumber=false
      case "$output" in
        "DP-1")      # Samsung: should be 11-20
          if [ "$ws" -lt 11 ] || [ "$ws" -gt 20 ]; then
            offset=10
            should_renumber=true
          fi
          ;;
        "DP-2")      # NSL: should be 21-30
          if [ "$ws" -lt 21 ] || [ "$ws" -gt 30 ]; then
            offset=20
            should_renumber=true
          fi
          ;;
        "HDMI-A-1")  # Philips: should be 31-40
          if [ "$ws" -lt 31 ] || [ "$ws" -gt 40 ]; then
            offset=30
            should_renumber=true
          fi
          ;;
        "DP-3")      # BNQ: should be 41-50
          if [ "$ws" -lt 41 ] || [ "$ws" -gt 50 ]; then
            offset=40
            should_renumber=true
          fi
          ;;
      esac

      if [ "$should_renumber" = true ]; then
        # Calculate new workspace number
        new_ws=$((ws + offset))

        echo "Renumbering workspace $ws on $output to $new_ws (correct range)" >> "$LOG_FILE"
        echo "DESK: Renumbering workspace $ws to $new_ws on $output" >&2
        $SWAYMSG_BIN "rename workspace \"$ws\" to \"$new_ws\"" >/dev/null 2>&1
        renumbered_count=$((renumbered_count + 1))
      else
        echo "Workspace $ws on $output is already in correct range" >> "$LOG_FILE"
      fi
    fi
  fi
done

echo "Renumbered $renumbered_count workspaces to correct ranges" >> "$LOG_FILE"

# Log final state
echo "=== POST-ASSIGNMENT STATE ===" >> "$LOG_FILE"
$SWAYMSG_BIN -t get_workspaces 2>/dev/null | $JQ_BIN -r '.[] | "Workspace \(.name) -> \(.output) (focused: \(.focused))"' >> "$LOG_FILE" 2>&1 || echo "Failed to get final workspace state" >> "$LOG_FILE"

echo "DESK: Hardware-ID-based workspace assignment complete" >&2
echo "=== WORKSPACE ASSIGNMENT COMPLETE ===" >> "$LOG_FILE"
echo "Total execution time: $(($(date +%s) - $(head -2 "$LOG_FILE" | tail -1 | cut -d' ' -f2- | xargs date +%s 2>/dev/null || echo 0))) seconds" >> "$LOG_FILE"
exit 0


