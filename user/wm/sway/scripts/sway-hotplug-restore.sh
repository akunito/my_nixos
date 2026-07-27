#!/usr/bin/env bash
set -uo pipefail

# Focus-immune monitor-hotplug handler (run by kanshi on every profile apply,
# i.e. whenever the set of active outputs changes).
#
# Replaces the legacy `swaysome init` + `rearrange-workspaces` +
# swaysome-assign-groups.sh exec chain, whose per-output `focus output` /
# `swaysome focus 1` dance forced every monitor's visible workspace back to X1
# and raced focus_follows_mouse (one overlapping run per reconnecting monitor).
#
# What it does instead:
#   1. Waits for sway to settle (declarative `workspace N output` pins already
#      move workspaces back to their monitors natively).
#   2. Migrates windows off ungrouped group-0 workspaces (1-10) into the
#      output's pinned decade (workspace-output-pins.conf, hardware-ID based),
#      by con_id — no focus changes.
#   3. If sway-snapshot-daemon.sh has a snapshot for the NEW monitor set
#      (same sway session), restores: visible workspace per output, focused
#      workspace, and floating windows' workspace + absolute position.
#   4. Re-fits any floating window that ended up straddling two outputs or
#      fully off its workspace's output (evacuation artifact): shrink to fit
#      and center it on its workspace's output.
#
# Idempotent; serialized via flock so bursts of kanshi applies queue up.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG="$(command -v swaymsg 2>/dev/null || true)"
JQ="$(command -v jq 2>/dev/null || true)"
[ -n "$SWAYMSG" ] && [ -n "$JQ" ] || exit 0

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_DIR="$RUNTIME/sway-hotplug"
PINS_CONF="$HOME/.config/sway/workspace-output-pins.conf"

exec 9>"$RUNTIME/sway-hotplug-restore.lock"
flock 9 || exit 0

# Let sway finish re-placing pinned workspaces on the (re)enabled outputs and
# coalesce the burst of kanshi applies when several monitors return together.
sleep 1.5

OUTPUTS="$($SWAYMSG -t get_outputs -r 2>/dev/null)" || exit 0
WS="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || exit 0

# --- Pins: hardware ID -> workspace decade base (group*10) -------------------
declare -A PIN_BASE
if [ -f "$PINS_CONF" ]; then
  while IFS='|' read -r grp crit; do
    [ -n "$grp" ] && [ -n "$crit" ] || continue
    case "$grp" in '#'*) continue ;; esac
    PIN_BASE["$crit"]=$((grp * 10))
  done <"$PINS_CONF"
fi

hwid_of_output() {
  $JQ -r --arg o "$1" \
    '.[] | select(.name==$o) | (.make+" "+.model+" "+.serial)' <<<"$OUTPUTS" | head -n1
}

# --- 1. Migrate group-0 orphans (workspaces 1-10) into the real decade -------
ORPHANS="$($JQ -r '.[] | select(.num>=1 and .num<=10) | "\(.name)\t\(.output)"' <<<"$WS")"
if [ -n "$ORPHANS" ]; then
  while IFS=$'\t' read -r wsname output; do
    [ -n "$wsname" ] || continue
    base=""
    hwid="$(hwid_of_output "$output")"
    if [ -n "$hwid" ] && [ -n "${PIN_BASE[$hwid]:-}" ]; then
      base="${PIN_BASE[$hwid]}"
    else
      # No pin for this output: fall back to its lowest existing decade.
      base="$($JQ -r --arg o "$output" \
        '[.[] | select(.output==$o and .num>=11) | ((.num/10)|floor)*10] | min // empty' <<<"$WS")"
    fi
    [ -n "$base" ] || continue
    target=$((base + 1))
    ids="$($SWAYMSG -t get_tree -r 2>/dev/null | $JQ -r --arg w "$wsname" \
      '.. | select(.type?=="workspace" and .name==$w)
          | [recurse(.nodes[]?, .floating_nodes[]?)
             | select(.type=="con" or .type=="floating_con") | .id] | .[]')"
    for id in $ids; do
      $SWAYMSG "[con_id=$id] move container to workspace number $target" >/dev/null 2>&1 || true
    done
  done <<<"$ORPHANS"
  WS="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || exit 0
fi

# --- 2. Restore snapshot for this monitor set (same sway session only) -------
SIG="$($JQ -r '[.[] | select(.active==true) | (.make+" "+.model+" "+.serial)] | sort | join("||")' <<<"$OUTPUTS")"
SNAP="$STATE_DIR/$(printf '%s' "$SIG" | sha256sum | cut -c1-16).json"

if [ -f "$SNAP" ]; then
  SNAP_SOCK="$($JQ -r '.swaysock // ""' "$SNAP" 2>/dev/null || echo "")"
  if [ -n "$SNAP_SOCK" ] && [ "$SNAP_SOCK" = "${SWAYSOCK:-}" ]; then
    FOCUSED="$($JQ -r '.focused // ""' "$SNAP")"

    # Visible workspace per output (skip the focused one; it is restored last
    # so final focus lands where it was before the monitors went off).
    while IFS= read -r vws; do
      [ -n "$vws" ] && [ "$vws" != "$FOCUSED" ] || continue
      $SWAYMSG "workspace \"$vws\"" >/dev/null 2>&1 || true
    done < <($JQ -r '.visible[]?.ws' "$SNAP")

    # Floating windows: back to their workspace and absolute position.
    # con_ids are stable within a sway session; vanished windows are skipped.
    TREE="$($SWAYMSG -t get_tree -r 2>/dev/null)" || TREE='{}'
    while IFS=$'\t' read -r cid fws fx fy; do
      [ -n "$cid" ] || continue
      exists="$($JQ -r --argjson id "$cid" \
        '[.. | select(.id? == $id)] | length' <<<"$TREE")"
      [ "$exists" != "0" ] || continue
      $SWAYMSG "[con_id=$cid] move container to workspace \"$fws\"" >/dev/null 2>&1 || true
      $SWAYMSG "[con_id=$cid] move absolute position $fx $fy" >/dev/null 2>&1 || true
    done < <($JQ -r '.floating[]? | "\(.con_id)\t\(.ws)\t\(.x)\t\(.y)"' "$SNAP")

    if [ -n "$FOCUSED" ]; then
      $SWAYMSG "workspace \"$FOCUSED\"" >/dev/null 2>&1 || true
    fi
  fi
fi

# --- 3. Re-fit floating windows straddling outputs or off their output ------
# A window evacuated from a larger monitor can be wider than the one it landed
# on (e.g. Samsung-sized kitty on the portrait NSL): shrink to fit the output
# of its workspace and center it there. Windows that sit cleanly on exactly
# one output with their center on their workspace's output are left alone.
TREE="$($SWAYMSG -t get_tree -r 2>/dev/null)" || exit 0
WS="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || exit 0

$JQ -n -r --argjson tree "$TREE" --argjson ws "$WS" --argjson outs "$OUTPUTS" '
  def ovl($a; $b):
    ((([$a.x + $a.width,  $b.x + $b.width ] | min) - ([$a.x, $b.x] | max)) > 8)
    and
    ((([$a.y + $a.height, $b.y + $b.height] | min) - ([$a.y, $b.y] | max)) > 8);
  [$outs[] | select(.active==true)] as $act
  | ($ws | map({key: .name, value: .output}) | from_entries) as $wsout
  | ($act | map({key: .name, value: .rect}) | from_entries) as $orects
  | $tree
  | recurse(.nodes[]?)
  | select(.type? == "workspace" and ((.name // "") | startswith("__") | not)) as $w
  | $w.floating_nodes[]?
  | . as $f
  | ($orects[$wsout[$w.name] // ""] // null) as $orect
  | select($orect != null)
  | ([$act[] | select(ovl(.rect; $f.rect))] | length) as $novl
  | (($f.rect.x + $f.rect.width / 2)  >= $orect.x
     and ($f.rect.x + $f.rect.width / 2)  < $orect.x + $orect.width
     and ($f.rect.y + $f.rect.height / 2) >= $orect.y
     and ($f.rect.y + $f.rect.height / 2) < $orect.y + $orect.height) as $centered
  | (($f.rect.x >= $orect.x - 48)
     and ($f.rect.y >= $orect.y - 48)
     and ($f.rect.x + $f.rect.width  <= $orect.x + $orect.width  + 48)
     and ($f.rect.y + $f.rect.height <= $orect.y + $orect.height + 48)) as $fits
  | select($novl != 1 or ($centered | not) or ($fits | not))
  | (if $f.rect.width  > ($orect.width  - 16) then $orect.width  - 16 else $f.rect.width  end) as $nw
  | (if $f.rect.height > ($orect.height - 16) then $orect.height - 16 else $f.rect.height end) as $nh
  | "[con_id=\($f.id)] resize set \($nw | floor) px \($nh | floor) px, move position center"
' | while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  $SWAYMSG "$cmd" >/dev/null 2>&1 || true
done

exit 0
