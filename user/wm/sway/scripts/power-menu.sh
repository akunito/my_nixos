#!/bin/sh
# Power menu using rofi
# Options: Lock, Logout, Restart, Shutdown, Suspend, Hibernate

CHOICE=$(echo -e "Lock\nLogout\nRestart\nShutdown\nSuspend\nHibernate" | rofi -dmenu -p "Power Menu:")

case $CHOICE in
    Lock)
        # CRITICAL: Use swaylock-effects, not swaylock
        swaylock --screenshots --clock --indicator --indicator-radius 100 --indicator-thickness 7 --effect-blur 7x5 --effect-vignette 0.5:0.5 --ring-color bb00cc --key-hl-color 880033
        ;;
    Logout)
        swaymsg exit
        ;;
    Restart)
        systemctl reboot
        ;;
    Shutdown)
        systemctl poweroff
        ;;
    Suspend)
        systemctl suspend
        ;;
    Hibernate)
        systemctl hibernate
        ;;
esac

