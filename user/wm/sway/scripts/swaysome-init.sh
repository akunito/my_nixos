#!/bin/sh
# Initialize swaysome and assign workspace groups to monitors

set -eu

# kanshi runs this script from a minimal systemd user unit; ensure basic tools are on PATH.
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:${HOME:-}/.nix-profile/bin:/usr/bin:/bin:${PATH:-}"

# This script must be safe for ALL profiles (not DESK-specific).
# Keep it non-opinionated: no hardcoded output names, no forced workspace jumps.

# Wait briefly for Sway IPC to be ready and outputs to be enumerated.
i=0
while [ "$i" -lt 30 ]; do
  if swaymsg -t get_outputs >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

# Optional: if swaysome is present, try to rearrange already-opened workspaces to the correct outputs.
# (This is idempotent and helps after hotplug or when old workspaces existed before swaysome init.)
if command -v swaysome >/dev/null 2>&1; then
  swaysome rearrange-workspaces >/dev/null 2>&1 || true
fi

