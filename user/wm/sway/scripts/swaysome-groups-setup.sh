#!/usr/bin/env bash
set -uo pipefail

# Assign per-output swaysome workspace groups and eliminate the ungrouped
# "group 0" default workspace.
#
# swaysome encodes a monitor's group in the tens digit of its workspace numbers
# (group 1 = 11-20, group 2 = 21-30, ...). `swaysome init 1` assigns each output
# a group starting at 1 (by output position) and `rearrange-workspaces` places
# each workspace on its correct output.
#
# Group 0 (workspaces 1-10) is intentionally NEVER used as a monitor group:
# swaysome has quirks there (e.g. `move`/next-workspace from ws "1" misbehaves)
# and it has no stable per-monitor identity. But sway auto-creates workspace "1"
# at login and autostart apps land on it before groups are assigned, so this
# script also migrates any windows on a group-0 workspace into the real group of
# the output they sit on, after which the empty orphan auto-removes.
#
# Idempotent and focus-immune (targets containers by con_id + explicit workspace
# number, so it is unaffected by focus_follows_mouse). Safe to run repeatedly and
# on every monitor hotplug.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG="$(command -v swaymsg 2>/dev/null || true)"
JQ="$(command -v jq 2>/dev/null || true)"
SWAYSOME="$(command -v swaysome 2>/dev/null || true)"

[ -n "$SWAYMSG" ] && [ -n "$JQ" ] && [ -n "$SWAYSOME" ] || exit 0

# 1. Assign groups (1, 2, ... by output position) and place workspaces.
"$SWAYSOME" init 1 >/dev/null 2>&1 || true
"$SWAYSOME" rearrange-workspaces >/dev/null 2>&1 || true

# 2. Migrate windows off any group-0 orphan (workspace num 1-10) into the real
#    group of its current output.
orphans="$("$SWAYMSG" -t get_workspaces 2>/dev/null \
  | "$JQ" -r '.[] | select(.num>=1 and .num<=10) | "\(.name)\t\(.output)"')"

[ -n "$orphans" ] || exit 0

while IFS="$(printf '\t')" read -r wsname output; do
  [ -n "$wsname" ] || continue

  # Real group base for this output = lowest tens block among its grouped
  # workspaces (num >= 11). If the output has no real group yet (init has not
  # given it one), skip — a later run (after settle) will have one.
  base="$("$SWAYMSG" -t get_workspaces 2>/dev/null \
    | "$JQ" -r --arg o "$output" \
      '[.[] | select(.output==$o and .num>=11) | ((.num/10)|floor)*10] | min // empty')"
  [ -n "$base" ] || continue

  target=$((base + 1))

  ids="$("$SWAYMSG" -t get_tree 2>/dev/null \
    | "$JQ" -r --arg w "$wsname" \
      '.. | select(.type?=="workspace" and .name==$w)
            | [recurse(.nodes[]?, .floating_nodes[]?)
               | select(.type=="con" or .type=="floating_con") | .id] | .[]')"
  for id in $ids; do
    "$SWAYMSG" "[con_id=$id] move container to workspace number $target" >/dev/null 2>&1 || true
  done
done <<< "$orphans"

exit 0
