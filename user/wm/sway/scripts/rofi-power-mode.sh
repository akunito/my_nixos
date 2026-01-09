#!/usr/bin/env bash
set -euo pipefail

# Rofi script-mode: power actions with icons.
# - Called with no args: prints menu entries.
# - Called with 1+ args: executes the selected entry.

# Make PATH reliable for systemd/Waybar contexts too
PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
SYSTEMCTL_BIN="$(command -v systemctl 2>/dev/null || true)"
SWAYLOCK_BIN="$(command -v swaylock 2>/dev/null || true)"

[ -n "$SYSTEMCTL_BIN" ] || SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
[ -n "$SWAYMSG_BIN" ] || SWAYMSG_BIN="/run/current-system/sw/bin/swaymsg"

print_item() {
  local label="$1"
  local icon="$2"
  # Rofi dmenu icon hint: <label>\0icon\x1f<icon-name>
  printf '%s\0icon\x1f%s\n' "$label" "$icon"
}

if [ "$#" -eq 0 ]; then
  print_item "Lock" "system-lock-screen"
  print_item "Logout" "system-log-out"
  print_item "Restart" "system-reboot"
  print_item "Shutdown" "system-shutdown"
  print_item "Suspend" "system-suspend"
  print_item "Hibernate" "system-hibernate"
  exit 0
fi

CHOICE="$1"

case "$CHOICE" in
  Lock)
    # Prefer swaylock-effects (your config uses swaylock-effects package but binary is still "swaylock")
    if [ -n "$SWAYLOCK_BIN" ]; then
      "$SWAYLOCK_BIN" --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 \
        --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033
    fi
    ;;
  Logout)
    "$SWAYMSG_BIN" exit
    ;;
  Restart)
    "$SYSTEMCTL_BIN" reboot
    ;;
  Shutdown)
    "$SYSTEMCTL_BIN" poweroff
    ;;
  Suspend)
    "$SYSTEMCTL_BIN" suspend
    ;;
  Hibernate)
    "$SYSTEMCTL_BIN" hibernate
    ;;
  *)
    # Unknown input (e.g. user typed custom text)
    exit 0
    ;;
esac


