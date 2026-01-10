#!/usr/bin/env bash
set -euo pipefail

# Report custom idle inhibit status for Waybar.
# Uses systemd --user service: idle-inhibit.service

SERVICE="idle-inhibit.service"

SYSTEMCTL_BIN="$(command -v systemctl || true)"
if [[ -z "$SYSTEMCTL_BIN" ]] && [[ -x /run/current-system/sw/bin/systemctl ]]; then
  SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
fi

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

active="false"
if [[ -n "$SYSTEMCTL_BIN" ]]; then
  if "$SYSTEMCTL_BIN" --user is-active --quiet "$SERVICE" 2>/dev/null; then
    active="true"
  fi
fi

if [[ "$active" == "true" ]]; then
  text=" "
  cls="activated"
  tip="Idle inhibit: ON

Click or Hyper+Mute: toggle"
else
  text=""
  cls="deactivated"
  tip="Idle inhibit: OFF

Click or Hyper+Mute: toggle"
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(json_escape "$text")" "$(json_escape "$tip")" "$cls"


