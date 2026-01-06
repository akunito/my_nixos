#!/bin/sh
# Debug script for Sway startup issues
# Logs to /home/akunito/.dotfiles/.cursor/debug.log

LOG_FILE="/home/akunito/.dotfiles/.cursor/debug.log"
TIMESTAMP=$(date +%s)

# Function to log JSON
log_json() {
  echo "{\"id\":\"log_${TIMESTAMP}_$(date +%N)\",\"timestamp\":$(date +%s)000,\"location\":\"debug-startup.sh:$1\",\"message\":\"$2\",\"data\":$3,\"sessionId\":\"sway-debug\",\"runId\":\"startup\",\"hypothesisId\":\"$4\"}" >> "$LOG_FILE"
}

# #region agent log - Hypothesis A: GTK_THEME not set
log_json "GTK_ENV_CHECK" "Checking GTK environment variables" "{\"GTK_THEME\":\"${GTK_THEME:-not_set}\",\"GTK_ICON_THEME\":\"${GTK_ICON_THEME:-not_set}\",\"GTK_APPLICATION_PREFER_DARK_THEME\":\"${GTK_APPLICATION_PREFER_DARK_THEME:-not_set}\"}" "A"
# #endregion

# #region agent log - Hypothesis B: GTK settings file check
if [ -f "$HOME/.config/gtk-3.0/settings.ini" ]; then
  GTK_SETTINGS=$(cat "$HOME/.config/gtk-3.0/settings.ini" | grep -E "gtk-theme-name|gtk-application-prefer-dark-theme" || echo "no_dark_settings")
  log_json "GTK_SETTINGS_FILE" "GTK settings file exists" "{\"content\":\"$GTK_SETTINGS\"}" "B"
else
  log_json "GTK_SETTINGS_FILE" "GTK settings file does not exist" "{\"path\":\"$HOME/.config/gtk-3.0/settings.ini\"}" "B"
fi
# #endregion

# #region agent log - Hypothesis C: Stylix GTK theme
if [ -f "$HOME/.config/gtk-3.0/settings.ini" ]; then
  STYLIX_THEME=$(grep "gtk-theme-name" "$HOME/.config/gtk-3.0/settings.ini" | grep -i "stylix\|dark" || echo "no_stylix_theme")
  log_json "STYLIX_GTK_THEME" "Checking for Stylix dark theme" "{\"theme_line\":\"$STYLIX_THEME\"}" "C"
fi
# #endregion

# #region agent log - Hypothesis A: Waybar command check
WAYBAR_PATH=$(which waybar 2>/dev/null || echo "not_found")
WAYBAR_EXISTS=$(test -f "/run/current-system/sw/bin/waybar" 2>/dev/null && echo "exists" || test -f "$HOME/.nix-profile/bin/waybar" 2>/dev/null && echo "exists" || echo "not_found")
log_json "WAYBAR_PATH_CHECK" "Checking waybar binary" "{\"which_waybar\":\"$WAYBAR_PATH\",\"exists\":\"$WAYBAR_EXISTS\"}" "A"
# #endregion

# #region agent log - Hypothesis B: Waybar config check
if [ -f "$HOME/.config/waybar/config" ] || [ -f "$HOME/.config/waybar/config.json" ]; then
  WAYBAR_CONFIG_ERROR=$(waybar --check-config 2>&1 || echo "config_error")
  log_json "WAYBAR_CONFIG_CHECK" "Checking waybar config syntax" "{\"error\":\"$WAYBAR_CONFIG_ERROR\"}" "B"
else
  log_json "WAYBAR_CONFIG_CHECK" "Waybar config file not found" "{\"path\":\"$HOME/.config/waybar\"}" "B"
fi
# #endregion

# #region agent log - Hypothesis C: Waybar process check
WAYBAR_PROCESS=$(pgrep -x waybar || echo "not_running")
log_json "WAYBAR_PROCESS_CHECK" "Checking if waybar is running" "{\"pid\":\"$WAYBAR_PROCESS\"}" "C"
# #endregion

# #region agent log - Hypothesis D: Waybar layer/position
if [ -f "$HOME/.config/waybar/config" ] || [ -f "$HOME/.config/waybar/config.json" ]; then
  WAYBAR_LAYER=$(grep -i "layer" "$HOME/.config/waybar/config"* 2>/dev/null | head -1 || echo "not_found")
  WAYBAR_POSITION=$(grep -i "position" "$HOME/.config/waybar/config"* 2>/dev/null | head -1 || echo "not_found")
  log_json "WAYBAR_LAYER_POSITION" "Checking waybar layer and position" "{\"layer\":\"$WAYBAR_LAYER\",\"position\":\"$WAYBAR_POSITION\"}" "D"
fi
# #endregion

# #region agent log - Hypothesis E: Environment variables check
log_json "ENV_VARS" "Checking critical environment variables" "{\"WAYLAND_DISPLAY\":\"${WAYLAND_DISPLAY:-not_set}\",\"XDG_RUNTIME_DIR\":\"${XDG_RUNTIME_DIR:-not_set}\",\"SWAYSOCK\":\"${SWAYSOCK:-not_set}\"}" "E"
# #endregion

# #region agent log - Hypothesis D: SwayFX readiness check
SWAY_VERSION=$(swaymsg -t get_version 2>&1 || echo "swaymsg_failed")
log_json "SWAY_READY" "Checking if SwayFX is ready and responding" "{\"swaymsg_output\":\"$SWAY_VERSION\"}" "D"
# #endregion

# #region agent log - Hypothesis A: Waybar config file location check
WAYBAR_CONFIG_DIR="$HOME/.config/waybar"
WAYBAR_CONFIG_FILE=""
if [ -f "$WAYBAR_CONFIG_DIR/config" ]; then
  WAYBAR_CONFIG_FILE="$WAYBAR_CONFIG_DIR/config"
elif [ -f "$WAYBAR_CONFIG_DIR/config.json" ]; then
  WAYBAR_CONFIG_FILE="$WAYBAR_CONFIG_DIR/config.json"
fi
log_json "WAYBAR_CONFIG_LOCATION" "Checking waybar config file location" "{\"config_dir\":\"$WAYBAR_CONFIG_DIR\",\"config_file\":\"$WAYBAR_CONFIG_FILE\",\"dir_exists\":$(test -d "$WAYBAR_CONFIG_DIR" && echo true || echo false)}" "A"
# #endregion

# #region agent log - Hypothesis A: Rofi width config
if [ -f "$HOME/.config/rofi/config.rasi" ]; then
  ROFI_WIDTH=$(grep -i "width" "$HOME/.config/rofi/config.rasi" | head -1 || echo "not_found")
  log_json "ROFI_WIDTH_CHECK" "Checking rofi width configuration" "{\"width_line\":\"$ROFI_WIDTH\"}" "A"
fi
# #endregion

# #region agent log - Hypothesis B: Rofi theme width
if [ -f "$HOME/.config/rofi/themes/custom.rasi" ]; then
  ROFI_THEME_WIDTH=$(grep -i "width" "$HOME/.config/rofi/themes/custom.rasi" | head -1 || echo "not_found")
  log_json "ROFI_THEME_WIDTH_CHECK" "Checking rofi theme width" "{\"width_line\":\"$ROFI_THEME_WIDTH\"}" "B"
fi
# #endregion

