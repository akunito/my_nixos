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

# Lightweight action log for debugging restore behavior (tmpfs, size-capped).
LOG_FILE="$STATE_DIR/restore.log"
log() {
  mkdir -p "$STATE_DIR"
  [ "$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)" -lt 65536 ] || : >"$LOG_FILE"
  printf '%s %s\n' "$(date '+%m-%d %T')" "$*" >>"$LOG_FILE"
}

exec 9>"$RUNTIME/sway-hotplug-restore.lock"
flock 9 || exit 0

# --- Parking (opt-in: ~/.config/sway/hotplug-park.conf sets PARK=1) ----------
# A DisplayPort monitor switched OFF drops HPD exactly like an unplugged
# cable, so sway destroys the output and evacuates its workspaces onto the
# remaining monitors (measured on DESK 2026-09-07: both DP monitors do it).
# With PARK=1 the evacuated decade of a pinned-but-absent monitor is moved
# onto a HEADLESS clone of it (same mode/scale, placed at x>=20000 so the
# pointer cannot reach it) instead of staying piled on the other screen.
# Windows keep size, layout and fullscreen; when the monitor returns the pins
# bring the decade back and the clone is unplugged. `--evacuate` moves every
# parked workspace to the focused real output (the "it really is unplugged"
# escape hatch, bound to a key).
PARK=0
PARK_CONF="$HOME/.config/sway/hotplug-park.conf"
# shellcheck disable=SC1090
[ -f "$PARK_CONF" ] && . "$PARK_CONF"
PARKED_FILE="$STATE_DIR/parked.json"
GEOM_FILE="$STATE_DIR/geometry.json"
mkdir -p "$STATE_DIR"
[ -f "$PARKED_FILE" ] || echo '{}' >"$PARKED_FILE"
[ -f "$GEOM_FILE" ] || echo '{}' >"$GEOM_FILE"

is_headless() { case "$1" in HEADLESS-*) return 0 ;; *) return 1 ;; esac; }

evacuate_parked() {
  # Move every parked workspace to the focused real output, drop the clones.
  local focused ws_json
  focused="$($SWAYMSG -t get_outputs -r | $JQ -r '[.[] | select(.active==true and (.name|startswith("HEADLESS")|not))] | (map(select(.focused==true)) + .) | .[0].name // empty')"
  [ -n "$focused" ] || return 0
  ws_json="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || return 0
  while IFS= read -r wsname; do
    [ -n "$wsname" ] || continue
    $SWAYMSG "[workspace=\"^${wsname}\$\"] move workspace to output $focused" >/dev/null 2>&1 || true
    log "evacuate: ws $wsname -> $focused"
  done < <($JQ -r '.[] | select(.output|startswith("HEADLESS")) | .name' <<<"$ws_json")
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    $SWAYMSG "output $h unplug" >/dev/null 2>&1 || true
    log "evacuate: unplugged $h"
  done < <($SWAYMSG -t get_outputs -r | $JQ -r '.[] | select(.name|startswith("HEADLESS")) | .name')
  echo '{}' >"$PARKED_FILE"
}

if [ "${1:-}" = "--evacuate" ]; then
  evacuate_parked
  exit 0
fi

# Let sway finish re-placing pinned workspaces on the (re)enabled outputs and
# coalesce the burst of kanshi applies when several monitors return together.
sleep 1.5

OUTPUTS="$($SWAYMSG -t get_outputs -r 2>/dev/null)" || exit 0
WS="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || exit 0

# Remember the geometry of every real active output (by hardware id) so an
# absent one can be cloned faithfully later.
if $JQ -n --slurpfile old "$GEOM_FILE" --argjson outs "$OUTPUTS" '
    ($old[0] // {}) + ([ $outs[] | select(.active==true and (.name|startswith("HEADLESS")|not))
      | { key: (.make+" "+.model+" "+.serial),
          value: { name, w: .current_mode.width, h: .current_mode.height,
                   r: ((.current_mode.refresh // 60000) / 1000), scale, transform } } ] | from_entries)
  ' >"$GEOM_FILE.tmp" 2>/dev/null; then mv "$GEOM_FILE.tmp" "$GEOM_FILE"; else rm -f "$GEOM_FILE.tmp"; fi

if [ "$PARK" = "1" ] && [ -f "$PINS_CONF" ]; then
  ACTIVE_HW="$($JQ -r '[.[] | select(.active==true and (.name|startswith("HEADLESS")|not)) | (.make+" "+.model+" "+.serial)]' <<<"$OUTPUTS")"

  # 0a. Unpark: a parked monitor is back -> move its decade home, drop the clone.
  while IFS=$'\t' read -r head hw; do
    [ -n "$head" ] || continue
    if $JQ -e --arg hw "$hw" 'index($hw) != null' <<<"$ACTIVE_HW" >/dev/null; then
      real="$($JQ -r --arg hw "$hw" '.[] | select(.active==true and (.make+" "+.model+" "+.serial)==$hw) | .name' <<<"$OUTPUTS" | head -n1)"
      while IFS= read -r wsname; do
        [ -n "$wsname" ] || continue
        $SWAYMSG "[workspace=\"^${wsname}\$\"] move workspace to output $real" >/dev/null 2>&1 || true
      done < <($JQ -r --arg h "$head" '.[] | select(.output==$h) | .name' <<<"$WS")
      $SWAYMSG "output $head unplug" >/dev/null 2>&1 || true
      $JQ --arg h "$head" 'del(.[$h])' "$PARKED_FILE" >"$PARKED_FILE.tmp" && mv "$PARKED_FILE.tmp" "$PARKED_FILE"
      log "unpark: $hw back on $real, $head unplugged"
    elif ! $JQ -e --arg h "$head" 'map(select(.output==$h)) | length > 0' <<<"$WS" >/dev/null; then
      # Nothing left on the clone (windows closed): drop it, re-park later if needed.
      $SWAYMSG "output $head unplug" >/dev/null 2>&1 || true
      $JQ --arg h "$head" 'del(.[$h])' "$PARKED_FILE" >"$PARKED_FILE.tmp" && mv "$PARKED_FILE.tmp" "$PARKED_FILE"
      log "unpark: $head empty, unplugged"
    fi
  done < <($JQ -r 'to_entries[] | "\(.key)\t\(.value.hw)"' "$PARKED_FILE")
  OUTPUTS="$($SWAYMSG -t get_outputs -r 2>/dev/null)" || exit 0
  WS="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || exit 0

  # 0b. Park: a pinned monitor is absent and some of its decade exists -> clone + move.
  slot=0
  for hw in "${!PIN_BASE[@]}"; do
    base="${PIN_BASE[$hw]}"
    if $JQ -e --arg hw "$hw" 'index($hw) != null' <<<"$ACTIVE_HW" >/dev/null; then continue; fi
    if $JQ -e --arg hw "$hw" '[.[] | select(.hw==$hw)] | length > 0' "$PARKED_FILE" >/dev/null; then continue; fi
    decade_ws="$($JQ -r --argjson b "$base" '.[] | select(.num > $b and .num <= $b+10 and (.output|startswith("HEADLESS")|not)) | .name' <<<"$WS")"
    [ -n "$decade_ws" ] || continue
    before="$($JQ -r '[.[] | .name | select(startswith("HEADLESS"))] | sort' <<<"$OUTPUTS")"
    $SWAYMSG create_output >/dev/null 2>&1 || { log "park: create_output failed for $hw"; continue; }
    sleep 0.3
    OUTPUTS="$($SWAYMSG -t get_outputs -r 2>/dev/null)" || exit 0
    head="$($JQ -r --argjson before "$before" '[.[] | .name | select(startswith("HEADLESS"))] | sort | map(select(. as $n | $before | index($n) | not)) | .[0] // empty' <<<"$OUTPUTS")"
    [ -n "$head" ] || { log "park: no new HEADLESS output appeared for $hw"; continue; }
    slot=$((slot + 1))
    px=$((20000 + slot * 10000))
    geo="$($JQ -c --arg hw "$hw" '.[$hw] // empty' "$GEOM_FILE")"
    if [ -n "$geo" ]; then
      w="$($JQ -r .w <<<"$geo")"; h="$($JQ -r .h <<<"$geo")"; r="$($JQ -r .r <<<"$geo")"; sc="$($JQ -r .scale <<<"$geo")"; tr="$($JQ -r .transform <<<"$geo")"
      $SWAYMSG "output $head mode ${w}x${h}@${r}Hz pos $px 0 scale $sc transform $tr" >/dev/null 2>&1 \
        || $SWAYMSG "output $head pos $px 0 scale $sc" >/dev/null 2>&1 || true
    else
      $SWAYMSG "output $head pos $px 0" >/dev/null 2>&1 || true
    fi
    moved=0
    while IFS= read -r wsname; do
      [ -n "$wsname" ] || continue
      $SWAYMSG "[workspace=\"^${wsname}\$\"] move workspace to output $head" >/dev/null 2>&1 && moved=$((moved + 1))
    done <<<"$decade_ws"
    $JQ --arg h "$head" --arg hw "$hw" --arg t "$(date +%s)" '.[$h] = {hw: $hw, since: ($t|tonumber)}' "$PARKED_FILE" >"$PARKED_FILE.tmp" && mv "$PARKED_FILE.tmp" "$PARKED_FILE"
    log "park: $hw absent -> $head at $px,0 ($moved workspaces: $(tr '\n' ' ' <<<"$decade_ws"))"
  done
  # Never leave focus on a clone.
  focused_out="$($SWAYMSG -t get_outputs -r | $JQ -r '.[] | select(.focused==true) | .name')"
  if is_headless "$focused_out"; then
    real_vis="$($SWAYMSG -t get_workspaces -r | $JQ -r '[.[] | select(.visible==true and (.output|startswith("HEADLESS")|not))] | .[0].name // empty')"
    [ -n "$real_vis" ] && $SWAYMSG "workspace \"$real_vis\"" >/dev/null 2>&1 || true
    log "park: focus moved off $focused_out to ws $real_vis"
  fi
  OUTPUTS="$($SWAYMSG -t get_outputs -r 2>/dev/null)" || exit 0
  WS="$($SWAYMSG -t get_workspaces -r 2>/dev/null)" || exit 0
fi

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
# Preserve the digit: workspace "3" becomes "13" (base+3), NOT base+1 — the
# old collapse-into-X1 behavior dumped e.g. Brave from ws 3 onto Vivaldi's 11.
# Rename keeps the whole workspace (layout included); if the target workspace
# already exists, fall back to moving the windows into it one by one.
ORPHANS="$($JQ -r '.[] | select(.num>=1 and .num<=10) | "\(.name)\t\(.num)\t\(.output)"' <<<"$WS")"
if [ -n "$ORPHANS" ]; then
  while IFS=$'\t' read -r wsname wsnum output; do
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
    target=$((base + wsnum))
    target_exists="$($JQ -r --arg t "$target" \
      '[.[] | select(.name==$t)] | length' <<<"$WS")"
    if [ "$target_exists" = "0" ] && [ "$wsname" = "$wsnum" ]; then
      $SWAYMSG "rename workspace \"$wsname\" to \"$target\"" >/dev/null 2>&1 || true
      log "orphan: renamed ws $wsname -> $target ($output)"
      continue
    fi
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
SIG="$($JQ -r '[.[] | select(.active==true and (.name|startswith("HEADLESS")|not)) | (.make+" "+.model+" "+.serial)] | sort | join("||")' <<<"$OUTPUTS")"
SNAP="$STATE_DIR/$(printf '%s' "$SIG" | sha256sum | cut -c1-16).json"
log "run sig=[$SIG] snap=$([ -f "$SNAP" ] && basename "$SNAP" || echo none)"

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

    # Floating windows: back to their workspace, original SIZE, and absolute
    # position. Size must be restored too — while the monitors were off the
    # window was evacuated to a smaller output and shrunk to fit it (re-fit
    # pass below and/or sway itself), so position alone brings back a shrunk
    # window. con_ids are stable within a sway session; vanished windows are
    # skipped.
    TREE="$($SWAYMSG -t get_tree -r 2>/dev/null)" || TREE='{}'
    while IFS=$'\t' read -r cid fws fx fy fw fh; do
      [ -n "$cid" ] || continue
      exists="$($JQ -r --argjson id "$cid" \
        '[.. | select(.id? == $id)] | length' <<<"$TREE")"
      [ "$exists" != "0" ] || continue
      # A window the user has since hidden in the scratchpad stays there: a
      # day-old snapshot pulled kitty-tmux out of it on 2026-09-07.
      in_scratch="$($JQ -r --argjson id "$cid" \
        '[.. | select(.type? == "workspace" and .name == "__i3_scratch") | recurse(.nodes[]?, .floating_nodes[]?) | select(.id? == $id)] | length' <<<"$TREE")"
      [ "$in_scratch" = "0" ] || { log "skip con=$cid (in scratchpad)"; continue; }
      # ORDER MATTERS: the workspace move must come LAST. `move absolute
      # position` re-assigns a floating window to the VISIBLE workspace of
      # the output containing the coordinates — with the workspace move
      # first, a window belonging to a hidden workspace (Brave on 13) was
      # teleported onto the visible one (11) by the position command.
      # Position/size first, then workspace membership as the final word
      # (same-output workspace moves keep floating geometry).
      if [ -n "$fw" ] && [ -n "$fh" ] && [ "$fw" -gt 0 ] 2>/dev/null; then
        $SWAYMSG "[con_id=$cid] resize set $fw px $fh px" >/dev/null 2>&1 || true
      fi
      $SWAYMSG "[con_id=$cid] move absolute position $fx $fy" >/dev/null 2>&1 || true
      $SWAYMSG "[con_id=$cid] move container to workspace \"$fws\"" >/dev/null 2>&1 || true
      log "restored con=$cid ws=$fws pos=$fx,$fy size=${fw}x${fh}"
    done < <($JQ -r '.floating[]? | "\(.con_id)\t\(.ws)\t\(.x)\t\(.y)\t\(.w)\t\(.h)"' "$SNAP")

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
  | select(($wsout[$w.name] // "") | startswith("HEADLESS") | not)
  | $w.floating_nodes[]?
  | . as $f
  | ($orects[$wsout[$w.name] // ""] // null) as $orect
  | select($orect != null)
  # Skip degraded outputs (EDID read failure after resume leaves the monitor
  # at 640x480 fallback): never shrink windows to fit a bogus mode.
  | select($orect.width >= 700)
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
  log "refit: $cmd"
done

# --- 4. Games: re-assert fullscreen -----------------------------------------
# `for_window ... fullscreen enable` only fires at map time; an output
# evacuate/return cycle leaves gamescope un-fullscreened (and, once floating
# and un-fullscreened, gamescope shrinks to a few px). Put it back.
$JQ -r '
  .. | select(.type? == "con" or .type? == "floating_con")
  | select((.fullscreen_mode // 0) == 0)
  | select(((.app_id // "") | test("^[Gg]amescope$")) or ((.window_properties.class // "") | test("^([Gg]amescope|steam_app_)")))
  | .id' <<<"$TREE" | while IFS= read -r gid; do
  [ -n "$gid" ] || continue
  $SWAYMSG "[con_id=$gid] fullscreen enable" >/dev/null 2>&1 || true
  log "game: con=$gid fullscreen re-enabled"
done

exit 0
