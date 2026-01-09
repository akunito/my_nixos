#!/usr/bin/env bash
set -euo pipefail

# Launch rofi power mode in environments with minimal PATH (e.g., Waybar/systemd-user).
# Important: use the Home-Manager wrapped `rofi` from the user profile so ROFI_PLUGIN_PATH is set
# and plugin modes (calc/emoji/…) don't error.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

ROFI_BIN="$(command -v rofi 2>/dev/null || true)"
[ -n "$ROFI_BIN" ] || exit 0

exec "$ROFI_BIN" -show power -show-icons


