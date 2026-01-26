#!/bin/sh
echo "=== Shell Environment Variables ==="
echo "QT_QPA_PLATFORMTHEME='$QT_QPA_PLATFORMTHEME'"
echo "QT_STYLE_OVERRIDE='$QT_STYLE_OVERRIDE'"
echo "QT_PLUGIN_PATH='$QT_PLUGIN_PATH'"
echo "XDG_CURRENT_DESKTOP='$XDG_CURRENT_DESKTOP'"
echo "XDG_SESSION_TYPE='$XDG_SESSION_TYPE'"

echo -e "\n=== Kvantum Configuration ==="
if [ -f "$HOME/.config/Kvantum/kvantum.kvconfig" ]; then
    echo "File exists: ~/.config/Kvantum/kvantum.kvconfig"
    grep "theme=" "$HOME/.config/Kvantum/kvantum.kvconfig"
else
    echo "MISSING: ~/.config/Kvantum/kvantum.kvconfig"
fi

echo -e "\n=== Running KCalc Environment (if active) ==="
KCALC_PID=$(pgrep kcalc | head -n1)
if [ -n "$KCALC_PID" ]; then
    echo "KCalc PID: $KCALC_PID"
    cat /proc/$KCALC_PID/environ | tr '\0' '\n' | grep -E "QT_|XDG_CURRENT|DISPLAY|WAYLAND"
else
    echo "KCalc is not running."
fi

echo -e "\n=== Installed Kvantum Plugins ==="
find ~/.nix-profile/lib/qt6/plugins -name "*kvantum*" 2>/dev/null
find /run/current-system/sw/lib/qt6/plugins -name "*kvantum*" 2>/dev/null

echo -e "\n=== Systemd User Environment ==="
systemctl --user show-environment | grep "^QT_"
