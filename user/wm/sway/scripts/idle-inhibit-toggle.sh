#!/usr/bin/env bash
set -u

# Toggle idle behavior by starting/stopping swayidle.service (systemd --user).
# This matches the *real* effect of Waybar's built-in idle_inhibitor module.
#
# Semantics:
# - If swayidle is running => stop it => Idle INHIBITED (coffee ON)
# - If swayidle is stopped => start it => Idle ALLOWED (coffee OFF)

SERVICE="swayidle.service"

SYSTEMCTL_BIN="$(command -v systemctl || true)"
if [[ -z "$SYSTEMCTL_BIN" ]] && [[ -x /run/current-system/sw/bin/systemctl ]]; then
  SYSTEMCTL_BIN="/run/current-system/sw/bin/systemctl"
fi

NOTIFY_BIN="$(command -v notify-send || true)"
if [[ -z "$NOTIFY_BIN" ]] && [[ -x /run/current-system/sw/bin/notify-send ]]; then
  NOTIFY_BIN="/run/current-system/sw/bin/notify-send"
fi

# When invoked from Waybar (systemd user service), env can be minimal.
# Ensure we can reach the user bus for `systemctl --user` and `notify-send`.
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

# IMPORTANT: do not use `set -e` here; `is-active` returns non-zero when inactive.
state="$("$SYSTEMCTL_BIN" --user is-active "$SERVICE" 2>/dev/null || true)"
if [[ "$state" == "active" ]]; then
  "$SYSTEMCTL_BIN" --user stop "$SERVICE" >/dev/null 2>&1 || true
  msg="Idle Inhibit: ON (Swayidle Stopped)"
else
  # `systemctl status` exits non-zero when inactive; don't use it to check existence.
  load_state="$("$SYSTEMCTL_BIN" --user show -p LoadState --value "$SERVICE" 2>/dev/null || true)"
  if [[ "$load_state" != "loaded" ]]; then
    msg="Idle Inhibit: ERROR (${SERVICE} not loaded)"
  else
    # If the unit previously failed, this unblocks restart.
    "$SYSTEMCTL_BIN" --user reset-failed "$SERVICE" >/dev/null 2>&1 || true
    "$SYSTEMCTL_BIN" --user start "$SERVICE" >/dev/null 2>&1 || true
    msg="Idle Inhibit: OFF (Swayidle Running)"
  fi
fi

if [[ -n "$NOTIFY_BIN" ]]; then
  "$NOTIFY_BIN" -t 2000 "Idle inhibit" "$msg"
fi


