#!/usr/bin/env bash
# Diagnostic script for Blueman and Chromium dark mode issues
# Run this script to gather all diagnostic information

set -euo pipefail

LOG_FILE="$HOME/.dotfiles/.cursor/theme-diagnostics.log"

echo "=== Theme Diagnostics Script ===" | tee "$LOG_FILE"
echo "Started at: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 1. Check gsettings
echo "=== 1. GSETTINGS ===" | tee -a "$LOG_FILE"
echo "color-scheme:" | tee -a "$LOG_FILE"
gsettings get org.gnome.desktop.interface color-scheme 2>&1 | tee -a "$LOG_FILE" || echo "ERROR: gsettings command failed" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "gtk-theme:" | tee -a "$LOG_FILE"
gsettings get org.gnome.desktop.interface gtk-theme 2>&1 | tee -a "$LOG_FILE" || echo "ERROR: gsettings command failed" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "All keys:" | tee -a "$LOG_FILE"
gsettings list-keys org.gnome.desktop.interface 2>&1 | tee -a "$LOG_FILE" || echo "ERROR: gsettings command failed" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 2. Check environment variables
echo "=== 2. ENVIRONMENT VARIABLES ===" | tee -a "$LOG_FILE"
echo "Current shell environment:" | tee -a "$LOG_FILE"
env | grep -E "GTK_|QT_" | tee -a "$LOG_FILE" || echo "No GTK/QT variables found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Home Manager session vars:" | tee -a "$LOG_FILE"
if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
  grep -E "GTK_|QT_" "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" | tee -a "$LOG_FILE" || echo "No GTK/QT variables found" | tee -a "$LOG_FILE"
else
  echo "File not found: $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "Systemd user session environment:" | tee -a "$LOG_FILE"
systemctl --user show-environment 2>&1 | grep -E "GTK_|QT_" | tee -a "$LOG_FILE" || echo "No GTK/QT variables found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 3. Check XDG Desktop Portals
echo "=== 3. XDG DESKTOP PORTALS ===" | tee -a "$LOG_FILE"
echo "xdg-desktop-portal status:" | tee -a "$LOG_FILE"
systemctl --user status xdg-desktop-portal --no-pager -l 2>&1 | tee -a "$LOG_FILE" || echo "Service not found or error" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "xdg-desktop-portal-gtk status:" | tee -a "$LOG_FILE"
systemctl --user status xdg-desktop-portal-gtk --no-pager -l 2>&1 | tee -a "$LOG_FILE" || echo "Service not found or error" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "All portal services:" | tee -a "$LOG_FILE"
systemctl --user list-units --type=service 2>&1 | grep portal | tee -a "$LOG_FILE" || echo "No portal services found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 4. Check systemd user services (race condition check)
echo "=== 4. SYSTEMD USER SERVICES ===" | tee -a "$LOG_FILE"
echo "blueman-applet status:" | tee -a "$LOG_FILE"
systemctl --user status blueman-applet --no-pager -l 2>&1 | tee -a "$LOG_FILE" || echo "Service not found or error" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "blueman-applet service details:" | tee -a "$LOG_FILE"
systemctl --user show blueman-applet 2>&1 | grep -E "After|Wants|Requires|ExecStart" | tee -a "$LOG_FILE" || echo "Service not found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "All blueman services:" | tee -a "$LOG_FILE"
systemctl --user list-units --type=service 2>&1 | grep blueman | tee -a "$LOG_FILE" || echo "No blueman services found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 5. Check XSettings daemon (for XWayland apps)
echo "=== 5. XSETTINGS DAEMON ===" | tee -a "$LOG_FILE"
echo "D-Bus XSettings services:" | tee -a "$LOG_FILE"
dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>&1 | grep -i xsettings | tee -a "$LOG_FILE" || echo "No XSettings found on D-Bus" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "gsd-xsettings process:" | tee -a "$LOG_FILE"
pgrep -a gsd-xsettings 2>&1 | tee -a "$LOG_FILE" || echo "gsd-xsettings not running" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "xsettings processes:" | tee -a "$LOG_FILE"
pgrep -a xsettings 2>&1 | tee -a "$LOG_FILE" || echo "No xsettings processes found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 6. Check GTK config files
echo "=== 6. GTK CONFIG FILES ===" | tee -a "$LOG_FILE"
echo "GTK-3.0 settings:" | tee -a "$LOG_FILE"
if [ -f "$HOME/.config/gtk-3.0/settings.ini" ]; then
  cat "$HOME/.config/gtk-3.0/settings.ini" | tee -a "$LOG_FILE"
else
  echo "File not found: $HOME/.config/gtk-3.0/settings.ini" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "GTK-4.0 settings:" | tee -a "$LOG_FILE"
if [ -f "$HOME/.config/gtk-4.0/settings.ini" ]; then
  cat "$HOME/.config/gtk-4.0/settings.ini" | tee -a "$LOG_FILE"
else
  echo "File not found: $HOME/.config/gtk-4.0/settings.ini" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "GTK config directory listing:" | tee -a "$LOG_FILE"
ls -la "$HOME/.config/gtk-"* 2>&1 | tee -a "$LOG_FILE" || echo "No GTK config directories found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 7. Check Stylix-generated files
echo "=== 7. STYLIX-GENERATED FILES ===" | tee -a "$LOG_FILE"
echo "GTK-4.0 CSS file:" | tee -a "$LOG_FILE"
if [ -f "$HOME/.config/gtk-4.0/gtk.css" ]; then
  ls -la "$HOME/.config/gtk-4.0/gtk.css" | tee -a "$LOG_FILE"
  echo "First 20 lines:" | tee -a "$LOG_FILE"
  head -20 "$HOME/.config/gtk-4.0/gtk.css" | tee -a "$LOG_FILE"
else
  echo "File not found: $HOME/.config/gtk-4.0/gtk.css" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# 8. Check application processes
echo "=== 8. APPLICATION PROCESSES ===" | tee -a "$LOG_FILE"
echo "Blueman processes:" | tee -a "$LOG_FILE"
pgrep -a blueman 2>&1 | tee -a "$LOG_FILE" || echo "No blueman processes found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Chromium processes:" | tee -a "$LOG_FILE"
pgrep -a chromium 2>&1 | tee -a "$LOG_FILE" || echo "No chromium processes found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Blueman-manager environment:" | tee -a "$LOG_FILE"
BLUEMAN_PID=$(pgrep -f blueman-manager | head -1)
if [ -n "$BLUEMAN_PID" ]; then
  cat "/proc/$BLUEMAN_PID/environ" 2>/dev/null | tr '\0' '\n' | grep -E "GTK_|QT_" | tee -a "$LOG_FILE" || echo "No GTK/QT variables found" | tee -a "$LOG_FILE"
else
  echo "blueman-manager not running" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "Blueman-applet environment:" | tee -a "$LOG_FILE"
BLUEMAN_APPLET_PID=$(pgrep -f blueman-applet | head -1)
if [ -n "$BLUEMAN_APPLET_PID" ]; then
  cat "/proc/$BLUEMAN_APPLET_PID/environ" 2>/dev/null | tr '\0' '\n' | grep -E "GTK_|QT_" | tee -a "$LOG_FILE" || echo "No GTK/QT variables found" | tee -a "$LOG_FILE"
else
  echo "blueman-applet not running" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "Chromium environment:" | tee -a "$LOG_FILE"
CHROMIUM_PID=$(pgrep -f chromium | head -1)
if [ -n "$CHROMIUM_PID" ]; then
  cat "/proc/$CHROMIUM_PID/environ" 2>/dev/null | tr '\0' '\n' | grep -E "GTK_|QT_|GDK_BACKEND|WAYLAND" | tee -a "$LOG_FILE" || echo "No relevant variables found" | tee -a "$LOG_FILE"
else
  echo "chromium not running" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# 10. Check Chromium command-line flags
echo "=== 10. CHROMIUM COMMAND-LINE FLAGS ===" | tee -a "$LOG_FILE"
echo "Chromium process with flags:" | tee -a "$LOG_FILE"
ps aux | grep chromium | grep -v grep | tee -a "$LOG_FILE" || echo "No chromium processes found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Chromium flags file:" | tee -a "$LOG_FILE"
if [ -f "$HOME/.config/chromium-flags.conf" ]; then
  cat "$HOME/.config/chromium-flags.conf" | tee -a "$LOG_FILE"
else
  echo "File not found: $HOME/.config/chromium-flags.conf" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# 11. Check if apps are Flatpak
echo "=== 11. FLATPAK APPS ===" | tee -a "$LOG_FILE"
echo "Flatpak apps (chromium/blueman):" | tee -a "$LOG_FILE"
flatpak list --app 2>&1 | grep -E "chromium|blueman" | tee -a "$LOG_FILE" || echo "No matching Flatpak apps found" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Chromium Flatpak overrides:" | tee -a "$LOG_FILE"
flatpak override --show org.chromium.Chromium 2>&1 | tee -a "$LOG_FILE" || echo "Not a Flatpak app or not installed" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Blueman Flatpak overrides:" | tee -a "$LOG_FILE"
flatpak override --show org.blueman.Blueman 2>&1 | tee -a "$LOG_FILE" || echo "Not a Flatpak app or not installed" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 12. Check Flatpak GTK environment (if apps are Flatpak)
echo "=== 12. FLATPAK GTK ENVIRONMENT ===" | tee -a "$LOG_FILE"
if flatpak list --app 2>&1 | grep -q "org.chromium.Chromium"; then
  echo "Chromium Flatpak gsettings:" | tee -a "$LOG_FILE"
  flatpak run --command=gsettings org.chromium.Chromium get org.gnome.desktop.interface color-scheme 2>&1 | tee -a "$LOG_FILE" || echo "Failed to get gsettings" | tee -a "$LOG_FILE"
else
  echo "Chromium is not a Flatpak app" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# 14. Check if apps have their own config
echo "=== 14. APPLICATION CONFIG FILES ===" | tee -a "$LOG_FILE"
echo "Blueman config directory:" | tee -a "$LOG_FILE"
if [ -d "$HOME/.config/blueman" ]; then
  ls -la "$HOME/.config/blueman/" | tee -a "$LOG_FILE"
else
  echo "Directory not found: $HOME/.config/blueman/" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"
echo "Chromium config:" | tee -a "$LOG_FILE"
if [ -d "$HOME/.config/chromium" ]; then
  echo "Directory exists: $HOME/.config/chromium" | tee -a "$LOG_FILE"
  ls -la "$HOME/.config/chromium" | head -20 | tee -a "$LOG_FILE"
elif [ -f "$HOME/.config/chromium-flags.conf" ]; then
  cat "$HOME/.config/chromium-flags.conf" | tee -a "$LOG_FILE"
else
  echo "No chromium config found" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# 15. D-Bus activation environment check
echo "=== 15. D-BUS ACTIVATION ENVIRONMENT ===" | tee -a "$LOG_FILE"
echo "D-Bus check:" | tee -a "$LOG_FILE"
dbus-send --session --print-reply --dest=org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionCredentials string:org.freedesktop.DBus 2>&1 | head -20 | tee -a "$LOG_FILE" || echo "D-Bus check failed" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "=== Diagnostics Complete ===" | tee -a "$LOG_FILE"
echo "Finished at: $(date)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"

