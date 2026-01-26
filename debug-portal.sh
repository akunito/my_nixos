#!/usr/bin/env bash
# Debug script for Discord/Vesktop screen sharing issues on Sway
# Run this in your Sway session after trying to share screen

echo "=== Discord/Vesktop Screen Sharing Debug ==="
echo ""
echo "Date: $(date)"
echo ""

echo "=== 1. Environment Variables in systemd user session ==="
echo "Checking WAYLAND_DISPLAY, XDG_CURRENT_DESKTOP, SWAYSOCK:"
systemctl --user show-environment | grep -E "(WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP|SWAYSOCK)" || echo "❌ NONE FOUND!"
echo ""

echo "=== 2. Portal Service Status ==="
echo "xdg-desktop-portal.service:"
systemctl --user status xdg-desktop-portal.service --no-pager -n 0 2>&1 | head -4
echo ""
echo "xdg-desktop-portal-wlr.service:"
systemctl --user status xdg-desktop-portal-wlr.service --no-pager -n 0 2>&1 | head -4
echo ""
echo "xdg-desktop-portal-gtk.service:"
systemctl --user status xdg-desktop-portal-gtk.service --no-pager -n 0 2>&1 | head -4
echo ""

echo "=== 3. Portal Configuration ==="
echo "Config file: ~/.config/xdg-desktop-portal/portals.conf or sway.conf"
if [ -f ~/.config/xdg-desktop-portal/sway.conf ]; then
  echo "Found sway.conf:"
  cat ~/.config/xdg-desktop-portal/sway.conf
elif [ -f ~/.config/xdg-desktop-portal/portals.conf ]; then
  echo "Found portals.conf:"
  cat ~/.config/xdg-desktop-portal/portals.conf
else
  echo "⚠️  No portal config found in ~/.config/xdg-desktop-portal/"
fi
echo ""

echo "=== 4. Installed Portal Backends ==="
echo "Checking for portal packages:"
ls -la /usr/share/xdg-desktop-portal/portals/ 2>/dev/null || \
ls -la /run/current-system/sw/share/xdg-desktop-portal/portals/ 2>/dev/null || \
echo "⚠️  Could not find portal desktop files"
echo ""

echo "=== 5. PipeWire Status ==="
echo "pipewire.service:"
systemctl --user status pipewire.service --no-pager -n 0 2>&1 | head -4
echo ""
echo "wireplumber.service:"
systemctl --user status wireplumber.service --no-pager -n 0 2>&1 | head -4
echo ""

echo "=== 6. Portal Service Logs (last 20 lines) ==="
echo "xdg-desktop-portal.service:"
journalctl --user -u xdg-desktop-portal.service -n 20 --no-pager
echo ""
echo "xdg-desktop-portal-wlr.service:"
journalctl --user -u xdg-desktop-portal-wlr.service -n 20 --no-pager
echo ""

echo "=== 7. DBus Environment ==="
echo "Checking dbus session environment:"
dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.GetConnectionUnixProcessID string:org.freedesktop.portal.Desktop 2>&1 | head -5
echo ""

echo "=== 8. Current Sway Socket ==="
echo "SWAYSOCK from current shell: ${SWAYSOCK:-NOT SET}"
echo "Sway IPC sockets in /run/user/$(id -u):"
ls -la /run/user/$(id -u)/sway-ipc.*.sock 2>/dev/null || echo "❌ No sway sockets found!"
echo ""

echo "=== 9. XDG_RUNTIME_DIR ==="
echo "XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR:-NOT SET}"
echo ""

echo "=== Debug complete ==="
echo ""
echo "INSTRUCTIONS:"
echo "1. Try to share screen in Vesktop/Discord NOW (while this terminal is open)"
echo "2. After attempting, check logs again with:"
echo "   journalctl --user -u xdg-desktop-portal-wlr.service -f"
echo "3. Look for errors like 'failed to connect' or 'ConditionEnvironment'"
