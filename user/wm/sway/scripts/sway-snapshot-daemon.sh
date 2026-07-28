# Snapshot workspace/floating-window state keyed by the set of active outputs.
#
# For each distinct monitor set (signature = sorted hardware IDs of active
# outputs) this daemon keeps a JSON snapshot of:
#   - the visible workspace on each output
#   - the focused workspace
#   - every floating window's con_id, workspace and absolute geometry
#
# sway-hotplug-restore.sh (run by kanshi on output changes) restores the
# snapshot that matches the new monitor set, so turning monitors off and on
# puts workspaces, focus and floating windows back where they were.
#
# Keying by signature is what makes this safe: the workspace churn sway causes
# while evacuating a disappearing output is recorded under the DEGRADED set's
# signature and never overwrites the good snapshot of the full set.
#
# Runs as a systemd user service bound to sway-session.target
# (see hotplug-restore.nix). Wrapped by writeShellApplication: strict mode is
# on and coreutils/jq/swaymsg come from runtimeInputs.

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sway-hotplug"
mkdir -p "$STATE_DIR"

# Bail out cleanly (no on-failure restart storm) if sway is not reachable.
if ! swaymsg -t get_version >/dev/null 2>&1; then
  echo "sway IPC not reachable; exiting" >&2
  exit 0
fi

current_sig() {
  swaymsg -t get_outputs -r 2>/dev/null \
    | jq -r '[.[] | select(.active==true) | (.make+" "+.model+" "+.serial)] | sort | join("||")' 2>/dev/null
}

snapshot() {
  local outputs ws tree sig file
  outputs="$(swaymsg -t get_outputs -r 2>/dev/null)" || return 0
  sig="$(jq -r '[.[] | select(.active==true) | (.make+" "+.model+" "+.serial)] | sort | join("||")' <<<"$outputs" 2>/dev/null)" || return 0
  [ -n "$sig" ] || return 0
  ws="$(swaymsg -t get_workspaces -r 2>/dev/null)" || return 0
  tree="$(swaymsg -t get_tree -r 2>/dev/null)" || return 0
  file="$STATE_DIR/$(printf '%s' "$sig" | sha256sum | cut -c1-16).json"
  if jq -n \
    --argjson ws "$ws" --argjson tree "$tree" --arg sock "${SWAYSOCK:-}" '
    {
      swaysock: $sock,
      visible: [ $ws[] | select(.visible==true) | { output, ws: .name } ],
      focused: ([ $ws[] | select(.focused==true) | .name ] | first // ""),
      floating: [ $tree
        | recurse(.nodes[]?)
        | select(.type? == "workspace" and ((.name // "") | startswith("__") | not)) as $w
        | $w.floating_nodes[]?
        | { con_id: .id, ws: $w.name,
            x: .rect.x, y: .rect.y, w: .rect.width, h: .rect.height } ]
    }' >"$file.tmp" 2>/dev/null; then
    mv "$file.tmp" "$file"
  else
    rm -f "$file.tmp"
  fi
  return 0
}

# Initial snapshot of the current state.
LAST_SIG="$(current_sig)"
snapshot

# Re-snapshot on workspace/window events (debounced: drain event bursts, then
# capture once). When the monitor set changes, run the restore script instead
# of snapshotting: this daemon is the PRIMARY hotplug trigger — kanshi's
# single-wildcard `output *` profile only matches when exactly ONE head is
# connected (kanshi logs "no profile matched" with two monitors up), so its
# exec cannot be relied on for multi-monitor states. The restore script is
# flock-serialized and idempotent, so overlap with kanshi's exec is harmless.
# When sway exits the pipe closes and we exit cleanly.
swaymsg -t subscribe -m '["workspace","window","output"]' 2>/dev/null | while read -r _event; do
  while read -r -t 0.4 _event; do :; done
  SIG="$(current_sig)"
  if [ -n "$SIG" ] && [ "$SIG" != "$LAST_SIG" ]; then
    LAST_SIG="$SIG"
    "$HOME/.config/sway/scripts/sway-hotplug-restore.sh" >/dev/null 2>&1 &
  else
    snapshot
  fi
done || true

exit 0
