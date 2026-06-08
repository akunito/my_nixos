#!/usr/bin/env bash
set -euo pipefail

# Migrate windows off ungrouped "group 0" workspaces (swaysome reserves
# workspaces 1-10 for group 0, which is intentionally never used) into their
# monitor's real swaysome group.
#
# Why this exists: sway auto-creates workspace "1" at session start, and
# autostart apps land on it before swaysome init assigns groups. swaysome
# init/rearrange create the per-output group workspaces (11, 21, ...) but do
# NOT migrate that orphan "1" (or its windows) — it just gets shuffled between
# outputs and never receives a waybar label (group 0 is unlabeled). This sweep
# moves any window on a group-0 workspace to the first workspace of its output's
# group, after which the empty orphan auto-removes.
#
# Focus-immune: targets containers by con_id and explicit workspace number, so
# it is unaffected by focus_follows_mouse.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
JQ_BIN="$(command -v jq 2>/dev/null || true)"

[ -n "$SWAYMSG_BIN" ] || exit 0
[ -n "$JQ_BIN" ] || exit 0

# Remember focus so the sweep is non-disruptive.
FOCUSED_WS="$("$SWAYMSG_BIN" -t get_workspaces 2>/dev/null \
  | "$JQ_BIN" -r '.[] | select(.focused==true) | .name' | head -n1 || true)"

# Orphans = workspaces numbered 1-10 (group 0).
orphans="$("$SWAYMSG_BIN" -t get_workspaces 2>/dev/null \
  | "$JQ_BIN" -r '.[] | select(.num>=1 and .num<=10) | "\(.name)\t\(.output)"')"

[ -n "$orphans" ] || exit 0

while IFS="$(printf '\t')" read -r wsname output; do
  [ -n "$wsname" ] || continue

  # The output's group base = lowest tens block among its grouped workspaces.
  base="$("$SWAYMSG_BIN" -t get_workspaces 2>/dev/null \
    | "$JQ_BIN" -r --arg o "$output" \
      '[.[] | select(.output==$o and .num>=11) | ((.num/10)|floor)*10] | min // empty')"

  # No group exists on this output yet (swaysome init didn't run / no monitor
  # group). Skip rather than guess — running init first is the caller's job.
  [ -n "$base" ] || continue

  target=$((base + 1))

  # Move every container (tiled + floating) off the orphan workspace.
  ids="$("$SWAYMSG_BIN" -t get_tree 2>/dev/null \
    | "$JQ_BIN" -r --arg w "$wsname" \
      '.. | select(.type?=="workspace" and .name==$w)
            | [recurse(.nodes[]?, .floating_nodes[]?)
               | select(.type=="con" or .type=="floating_con") | .id] | .[]')"
  for id in $ids; do
    "$SWAYMSG_BIN" "[con_id=$id] move container to workspace number $target" >/dev/null 2>&1 || true
  done
done <<< "$orphans"

# Restore focus if it still exists (orphan workspaces may have auto-removed).
if [ -n "$FOCUSED_WS" ] \
   && "$SWAYMSG_BIN" -t get_workspaces 2>/dev/null | "$JQ_BIN" -e --arg w "$FOCUSED_WS" \
        'any(.[]; .name==$w)' >/dev/null 2>&1; then
  "$SWAYMSG_BIN" "workspace \"$FOCUSED_WS\"" >/dev/null 2>&1 || true
fi

exit 0
