#!/usr/bin/env bash
set -uo pipefail

# Close the login-timing race for swaysome workspace groups.
#
# At login the outputs and the session settle asynchronously, and swaysome init
# (run from kanshi when it applies) can fire before the built-in display is
# ready — leaving that monitor on the ungrouped default workspace "1" (group 0).
# Running the group setup again a few seconds later, once things have settled,
# reliably moves the monitor into a real group.
#
# Guarded: only re-runs the setup while a group-0 orphan (workspace num 1-10)
# actually exists, so once the groups are clean it stops touching anything and
# never disrupts the user mid-work. Self-terminates after its passes.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG="$(command -v swaymsg 2>/dev/null || true)"
JQ="$(command -v jq 2>/dev/null || true)"
SETUP="$HOME/.config/sway/scripts/swaysome-groups-setup.sh"

[ -n "$SWAYMSG" ] && [ -n "$JQ" ] && [ -x "$SETUP" ] || exit 0

# Passes at ~2s, ~5s, ~10s after launch to catch slow output/session settling.
for delay in 2 3 5; do
  sleep "$delay"
  if "$SWAYMSG" -t get_workspaces 2>/dev/null \
     | "$JQ" -e 'any(.[]; .num>=1 and .num<=10)' >/dev/null 2>&1; then
    "$SETUP" >/dev/null 2>&1 || true
  fi
done

exit 0
