#!/bin/sh

# Post hooks to be called after a
# configuration sync

# Mainly just to reload stylix

# xmonad
pgrep xmobar &> /dev/null && echo "Killing old xmobar instances" && echo "Running killall xmobar" && killall xmobar &> /dev/null; # xmonad will restart xmobar
pgrep xmonad &> /dev/null && echo "Recompiling xmonad" && echo "Running xmonad --recompile && xmonad --restart" && xmonad --recompile &> /dev/null && xmonad --restart &> /dev/null;
pgrep .dunst-wrapped &> /dev/null && echo "Restarting dunst" && killall .dunst-wrapped && echo "Running dunst" && dunst &> /dev/null & disown;
pgrep xmonad &> /dev/null && echo "Reapplying background from stylix via feh" && echo "Running ~/.fehbg-stylix" && ~/.fehbg-stylix &> /dev/null & disown;

# hyprland
pgrep Hyprland &> /dev/null && echo "Reloading hyprland" && hyprctl reload &> /dev/null;
if pgrep .waybar-wrapped &> /dev/null; then
  # IMPORTANT:
  # In Sway, Waybar is managed by systemd --user (waybar.service). Killing waybar and spawning a new
  # instance here causes duplicates: systemd restarts the service, and this script also launches one.
  if systemctl --user is-active --quiet waybar.service 2>/dev/null; then
    # Kill kded6 if running - it claims StatusNotifierWatcher but doesn't implement it properly
    if pgrep -x kded6 &>/dev/null; then
      echo "Killing kded6 (conflicts with waybar SNI)"
      pkill -x kded6 2>/dev/null || true
      sleep 0.3
    fi
    echo "Restarting waybar.service (systemd-managed)"
    systemctl --user restart waybar.service
    # Kill any stray non-systemd waybar instances (keep the service MainPID)
    MAINPID="$(systemctl --user show -p MainPID --value waybar.service 2>/dev/null || true)"
    if [ -n "$MAINPID" ] && [ "$MAINPID" != "0" ]; then
      for pid in $(pgrep -x waybar 2>/dev/null || true); do
        [ "$pid" = "$MAINPID" ] || kill "$pid" 2>/dev/null || true
      done
    fi
    # Restart tray apps so they re-register with new waybar SNI host
    sleep 1.5  # Wait for waybar to initialize SNI host
    for svc in nm-applet blueman-applet nextcloud-client sunshine; do
      if systemctl --user is-active --quiet "$svc.service" 2>/dev/null; then
        echo "Restarting $svc.service (re-register tray icon)"
        systemctl --user restart "$svc.service"
      fi
    done
  else
    echo "Restarting waybar (manually launched)"
    killall .waybar-wrapped &> /dev/null || true
    echo "Running waybar"
    waybar &> /dev/null & disown;
  fi
fi
pgrep fnott &> /dev/null && echo "Restarting fnott" && killall fnott && echo "Running fnott" && fnott &> /dev/null & disown;
pgrep hyprpaper &> /dev/null && echo "Reapplying background via hyprpaper" && killall hyprpaper && echo "Running hyprpaper" && hyprpaper &> /dev/null & disown;
pgrep nwggrid-server &> /dev/null && echo "Restarting nwggrid-server" && killall nwggrid-server && echo "Running nwggrid-wrapper" && nwggrid-wrapper &> /dev/null & disown;

# emacs
pgrep emacs &> /dev/null && echo "Reloading emacs stylix theme" && echo "Running emacsclient --no-wait --eval \"(load-theme 'doom-stylix t nil)\"" && emacsclient --no-wait --eval "(load-theme 'doom-stylix t nil)" &> /dev/null;
