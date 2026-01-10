#!/bin/sh
# Initialize swaysome and assign workspace groups to monitors

set -eu

# kanshi runs this script from a minimal systemd user unit; ensure basic tools are on PATH.
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:${HOME:-}/.nix-profile/bin:/usr/bin:/bin:${PATH:-}"

# Wait briefly for Sway IPC to be ready and outputs to be enumerated.
i=0
while [ "$i" -lt 30 ]; do
  if swaymsg -t get_outputs >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

# kanshi runs `${pkgs.swaysome}/bin/swaysome init` on every profile apply (startup + hotplug).
# Here we only ensure focus lands on the main monitor + its relative workspace 1 (which is ID 11 in Group 1).
MAIN_OUTPUT="Samsung Electric Company Odyssey G70NC H1AK500000"

# Return focus to main output (even if focus_follows_mouse would otherwise pull it away).
swaymsg focus output "$MAIN_OUTPUT" >/dev/null 2>&1 || true

# Focus relative workspace 1 on Group 1 (maps to workspace number 11).
swaysome focus 1 >/dev/null 2>&1 || true

