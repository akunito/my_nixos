#!/usr/bin/env bash
set -euo pipefail

# Waybar notifications module (Sway Notification Center)
# - Icon only (no counter shown)
# - Hidden when there are no notifications
#
# Usage: waybar-notifications.sh /nix/store/.../bin/swaync-client

SWAYNC_BIN="${1:-swaync-client}"

if ! command -v "$SWAYNC_BIN" >/dev/null 2>&1; then
  printf '{"text":"","tooltip":"swaync-client not found","class":"hidden"}\n'
  exit 0
fi

# Query state (skip-wait so it doesn't block if swaync is not yet up)
count="$("$SWAYNC_BIN" -c -sw 2>/dev/null || echo 0)"
dnd="$("$SWAYNC_BIN" -D -sw 2>/dev/null || echo false)"
inhibited="$("$SWAYNC_BIN" -I -sw 2>/dev/null || echo false)"

# Normalize
count="${count//[^0-9]/}"
[[ -n "$count" ]] || count=0

if [[ "$count" == "0" ]]; then
  printf '{"text":"","tooltip":"","class":"hidden"}\n'
  exit 0
fi

# Icons (Font Awesome / Nerd Font)
bell=""
dnd_icon=""
dot=""

icon="$bell"
if [[ "$dnd" == "true" ]]; then
  icon="$dnd_icon"
fi

text="${icon} ${dot}"

tip="Notifications: ${count}"
if [[ "$dnd" == "true" ]]; then
  tip="${tip}\nDND: on"
else
  tip="${tip}\nDND: off"
fi
if [[ "$inhibited" == "true" ]]; then
  tip="${tip}\nInhibited: yes"
fi
tip="${tip}\n\nLeft click: open panel\nRight click: clear all"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(json_escape "$text")" "$(json_escape "$tip")" "notification"


