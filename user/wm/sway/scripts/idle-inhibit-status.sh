#!/usr/bin/env bash
set -euo pipefail

# Report idle status for Waybar based on swayidle.service state.
# - swayidle active   => idle is allowed  => class deactivated
# - swayidle inactive => idle inhibited   => class activated

SERVICE="swayidle.service"

SYSTEMCTL_BIN="$(command -v systemctl || true)"
if [[ -z "$SYSTEMCTL_BIN" ]] && [[ -x /run/current-system/sw/bin/systemctl ]]; then
  SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
fi

ensure_user_bus_env() {
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    local uid
    uid="$(id -u)"
    if [[ -d "/run/user/${uid}" ]]; then
      export XDG_RUNTIME_DIR="/run/user/${uid}"
    fi
  fi

  if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
  fi
}

ensure_user_bus_env

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
  text=""
  cls="deactivated"
  tip="Idle Allowed

Click or Hyper+Mute: toggle"
else
  text=" "
  cls="activated"
  tip="Idle Inhibited (swayidle stopped)

Click or Hyper+Mute: toggle"
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(json_escape "$text")" "$(json_escape "$tip")" "$cls"


