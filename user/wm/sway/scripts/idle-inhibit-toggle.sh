#!/usr/bin/env bash
set -euo pipefail

# Toggle custom idle inhibit service and notify the user.
# Service: idle-inhibit.service (systemd --user)

SERVICE="idle-inhibit.service"

SYSTEMCTL_BIN="$(command -v systemctl || true)"
if [[ -z "$SYSTEMCTL_BIN" ]] && [[ -x /run/current-system/sw/bin/systemctl ]]; then
  SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
fi

NOTIFY_BIN="$(command -v notify-send || true)"
if [[ -z "$NOTIFY_BIN" ]] && [[ -x /run/current-system/sw/bin/notify-send ]]; then
  NOTIFY_BIN="/run/current-system/sw/bin/notify-send"
fi

# Prevent double-toggles if the key generates a fast down/up sequence.
runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
LOCK_DIR="${runtime_dir}/idle-inhibit-toggle.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if [[ -z "$SYSTEMCTL_BIN" ]]; then
  [[ -n "$NOTIFY_BIN" ]] && "$NOTIFY_BIN" -t 2000 "Idle inhibit" "systemctl not found" || true
  exit 0
fi

if "$SYSTEMCTL_BIN" --user is-active --quiet "$SERVICE" 2>/dev/null; then
  "$SYSTEMCTL_BIN" --user stop "$SERVICE" || true
  status="OFF"
else
  "$SYSTEMCTL_BIN" --user start "$SERVICE" || true
  status="ON"
fi

if [[ -n "$NOTIFY_BIN" ]]; then
  "$NOTIFY_BIN" -t 2000 "Idle inhibit" "Idle inhibit: ${status}"
fi


