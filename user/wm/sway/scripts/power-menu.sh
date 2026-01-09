#!/bin/sh
# Power menu using rofi
# Options: Lock, Logout, Restart, Shutdown, Suspend, Hibernate

#
# NOTE: This script is invoked both from Sway bindings and from Waybar (systemd user service).
# Waybar/systemd can have a minimal PATH, so we make PATH explicit here.
#
PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

ROFI_BIN="$(command -v rofi 2>/dev/null || true)"
SWAYMSG_BIN="$(command -v swaymsg 2>/dev/null || true)"
SYSTEMCTL_BIN="$(command -v systemctl 2>/dev/null || true)"
SWAYLOCK_BIN="$(command -v swaylock 2>/dev/null || true)"

[ -n "$ROFI_BIN" ] || exit 0
[ -n "$SYSTEMCTL_BIN" ] || SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
[ -n "$SWAYMSG_BIN" ] || SWAYMSG_BIN="/run/current-system/sw/bin/swaymsg"

CHOICE=$(
  printf "%s\n" "Lock" "Logout" "Restart" "Shutdown" "Suspend" "Hibernate" \
    | "$ROFI_BIN" -dmenu -p "Power Menu:"
)

case $CHOICE in
    Lock)
        # CRITICAL: Use swaylock-effects, not swaylock
        if [ -n "$SWAYLOCK_BIN" ]; then
          "$SWAYLOCK_BIN" --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033
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
esac

