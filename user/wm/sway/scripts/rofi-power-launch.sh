#!/usr/bin/env bash
set -euo pipefail

# Launch rofi power mode in environments with minimal PATH (e.g., Waybar/systemd-user).
# Important: use the Home-Manager wrapped `rofi` from the user profile so ROFI_PLUGIN_PATH is set
# and plugin modes (calc/emoji/…) don't error.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

if ! command -v swaymsg >/dev/null 2>&1; then
  command -v notify-send >/dev/null 2>&1 && notify-send -t 2000 "Error" "swaymsg missing (cannot launch power menu)" || true
  exit 1
fi

ROFI_BIN="$(command -v rofi 2>/dev/null || true)"
[ -n "$ROFI_BIN" ] || exit 0

# IMPORTANT: Waybar runs as a systemd user service and may not have the correct compositor/XWayland env.
# Delegate execution to Sway so the app inherits the live session environment.
swaymsg exec "rofi -show p -modi p:rofi-power-menu -theme-str 'window {width: 12em;} listview {lines: 6;}'"


