{ pkgs
, lib
, systemSettings
, writeSwaySessionEnv
, writeSwayPortalEnv
, ...
}:

let
  coreutils = "${pkgs.coreutils}/bin";
  python = "${pkgs.python3}/bin/python3";

  # NDJSON sink for this repo (debug-mode compatible).
  # NOTE: This file is intentionally inert until imported and wired into `user/wm/sway/default.nix`.
  logPath = "/home/akunito/.dotfiles/.cursor/debug.log";

  writeNdjson = pkgs.writeShellScriptBin "write-ndjson-log" ''
    #!/bin/sh
    # Usage: write-ndjson-log <hypothesisId> <location> <message> <json_data>
    set -u
    H="$1"; LOC="$2"; MSG="$3"; DATA="$4"
    TS="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"
    LOG_ID="log_${TS}_$$"
    LOG="${logPath}"
    LOG="$LOG" TS="$TS" LOG_ID="$LOG_ID" H="$H" LOC="$LOC" MSG="$MSG" DATA="$DATA" "${python}" - <<'PY'
import json, os
payload = {
  "id": os.environ.get("LOG_ID",""),
  "timestamp": int(os.environ.get("TS","0")),
  "location": os.environ.get("LOC",""),
  "message": os.environ.get("MSG",""),
  "data": json.loads(os.environ.get("DATA","{}")),
  "sessionId": "debug-session",
  "runId": "relog-debug",
  "hypothesisId": os.environ.get("H",""),
}
with open(os.environ["LOG"], "a", encoding="utf-8") as f:
  f.write(json.dumps(payload, separators=(",",":")) + "\n")
PY
  '';

  writeLog = "${writeNdjson}/bin/write-ndjson-log";

  # Debug wrapper: write the portal env file + log what was captured.
  write-sway-portal-env-debug = pkgs.writeShellScriptBin "write-sway-portal-env-debug" ''
    #!/bin/sh
    set -u
    TS="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"
    ENV_FILE="/run/user/$(${coreutils}/id -u)/sway-portal.env"

    # #region agent log
    ${writeLog} "H_PORTAL_ENV" "user/wm/sway/debug/relog-instrumentation.nix:write-sway-portal-env-debug:entry" \
      "About to write %t/sway-portal.env" \
      "{\"ts\":$TS,\"xdr\":\"''${XDG_RUNTIME_DIR:-}\",\"display\":\"''${DISPLAY:-}\",\"wayland_display\":\"''${WAYLAND_DISPLAY:-}\",\"swaysock\":\"''${SWAYSOCK:-}\",\"env_file\":\"$ENV_FILE\"}"
    # #endregion agent log

    "${writeSwayPortalEnv}/bin/write-sway-portal-env" >/dev/null 2>&1 || true

    ENV_EXISTS=false
    ENV_SIZE=0
    if [ -f "$ENV_FILE" ]; then
      ENV_EXISTS=true
      ENV_SIZE="$(${coreutils}/stat -c '%s' "$ENV_FILE" 2>/dev/null || echo 0)"
    fi

    # #region agent log
    ${writeLog} "H_PORTAL_ENV" "user/wm/sway/debug/relog-instrumentation.nix:write-sway-portal-env-debug:exit" \
      "Finished writing %t/sway-portal.env" \
      "{\"ts\":$TS,\"env_exists\":$ENV_EXISTS,\"env_size\":$ENV_SIZE}"
    # #endregion agent log
  '';

  # Debug wrapper: write the session env file + log what was captured.
  write-sway-session-env-debug = pkgs.writeShellScriptBin "write-sway-session-env-debug" ''
    #!/bin/sh
    set -u
    TS="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"
    ENV_FILE="/run/user/$(${coreutils}/id -u)/sway-session.env"

    # #region agent log
    ${writeLog} "H_ENV" "user/wm/sway/debug/relog-instrumentation.nix:write-sway-session-env-debug:entry" \
      "About to write %t/sway-session.env" \
      "{\"ts\":$TS,\"xdr\":\"''${XDG_RUNTIME_DIR:-}\",\"wayland_display\":\"''${WAYLAND_DISPLAY:-}\",\"swaysock\":\"''${SWAYSOCK:-}\",\"env_file\":\"$ENV_FILE\"}"
    # #endregion agent log

    "${writeSwaySessionEnv}/bin/write-sway-session-env" >/dev/null 2>&1 || true

    ENV_EXISTS=false
    ENV_SIZE=0
    ENV_MTIME=0
    if [ -f "$ENV_FILE" ]; then
      ENV_EXISTS=true
      ENV_SIZE="$(${coreutils}/stat -c '%s' "$ENV_FILE" 2>/dev/null || echo 0)"
      ENV_MTIME="$(${coreutils}/stat -c '%Y' "$ENV_FILE" 2>/dev/null || echo 0)"
    fi

    # #region agent log
    ${writeLog} "H_ENV" "user/wm/sway/debug/relog-instrumentation.nix:write-sway-session-env-debug:exit" \
      "Finished writing %t/sway-session.env" \
      "{\"ts\":$TS,\"env_exists\":$ENV_EXISTS,\"env_size\":$ENV_SIZE,\"env_mtime\":$ENV_MTIME}"
    # #endregion agent log
  '';

  # Debug wrapper: start sway-session.target and measure any blocking time in systemctl.
  sway-session-start-debug = pkgs.writeShellScriptBin "sway-session-start-debug" ''
    #!/bin/sh
    set -u
    TS_START="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"

    GS_ACTIVE="$(systemctl --user show -p ActiveState --value graphical-session.target 2>/dev/null || echo "unknown")"
    GS_SUB="$(systemctl --user show -p SubState --value graphical-session.target 2>/dev/null || echo "unknown")"

    # #region agent log
    ${writeLog} "H_SYSTEMD" "user/wm/sway/debug/relog-instrumentation.nix:sway-session-start-debug:pre_start" \
      "About to start sway-session.target" \
      "{\"ts\":$TS_START,\"graphical_session_active\":\"$GS_ACTIVE\",\"graphical_session_sub\":\"$GS_SUB\"}"
    # #endregion agent log

    systemctl --user start sway-session.target >/dev/null 2>&1
    RC="$?"

    TS_END="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"
    DURATION_MS=$((TS_END - TS_START))

    SS_ACTIVE="$(systemctl --user show -p ActiveState --value sway-session.target 2>/dev/null || echo "unknown")"
    SS_SUB="$(systemctl --user show -p SubState --value sway-session.target 2>/dev/null || echo "unknown")"
    WB_ACTIVE="$(systemctl --user show -p ActiveState --value waybar.service 2>/dev/null || echo "unknown")"
    WB_SUB="$(systemctl --user show -p SubState --value waybar.service 2>/dev/null || echo "unknown")"

    # #region agent log
    ${writeLog} "H_SYSTEMD" "user/wm/sway/debug/relog-instrumentation.nix:sway-session-start-debug:post_start" \
      "Started sway-session.target (systemctl returned)" \
      "{\"ts\":$TS_END,\"rc\":$RC,\"duration_ms\":$DURATION_MS,\"sway_session_active\":\"$SS_ACTIVE\",\"sway_session_sub\":\"$SS_SUB\",\"waybar_active\":\"$WB_ACTIVE\",\"waybar_sub\":\"$WB_SUB\"}"
    # #endregion agent log
  '';

  # ExecStartPre hook for waybar: record whether env + SWAYSOCK are valid right before launch.
  waybar-prestart-debug = pkgs.writeShellScriptBin "waybar-prestart-debug" ''
    #!/bin/sh
    set -u
    TS="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"
    ENV_FILE="/run/user/$(${coreutils}/id -u)/sway-session.env"

    SWAYSOCK_VAL="''${SWAYSOCK:-}"
    WAYLAND_DISPLAY_VAL="''${WAYLAND_DISPLAY:-}"

    ENV_EXISTS=false
    if [ -f "$ENV_FILE" ]; then ENV_EXISTS=true; fi

    SWAYSOCK_EXISTS=false
    if [ -n "$SWAYSOCK_VAL" ] && [ -S "$SWAYSOCK_VAL" ]; then SWAYSOCK_EXISTS=true; fi

    # #region agent log
    ${writeLog} "H_WAYBAR" "user/wm/sway/debug/relog-instrumentation.nix:waybar-prestart-debug:prestart" \
      "Waybar ExecStartPre snapshot" \
      "{\"ts\":$TS,\"env_exists\":$ENV_EXISTS,\"swaysock_set\":$([ -n "$SWAYSOCK_VAL" ] && echo true || echo false),\"swaysock_exists\":$SWAYSOCK_EXISTS,\"wayland_display_set\":$([ -n "$WAYLAND_DISPLAY_VAL" ] && echo true || echo false)}"
    # #endregion agent log
  '';

  # ExecStartPre hook for xdg-desktop-portal-gtk: capture env that determines backend selection.
  portal-gtk-prestart-debug = pkgs.writeShellScriptBin "portal-gtk-prestart-debug" ''
    #!/bin/sh
    set -u
    TS="$(${coreutils}/date +%s%3N 2>/dev/null || ${coreutils}/date +%s000)"
    ENV_FILE="/run/user/$(${coreutils}/id -u)/sway-portal.env"

    ENV_EXISTS=false
    if [ -f "$ENV_FILE" ]; then ENV_EXISTS=true; fi

    WAYLAND_DISPLAY_VAL="''${WAYLAND_DISPLAY:-}"
    SWAYSOCK_VAL="''${SWAYSOCK:-}"
    XDR_VAL="''${XDG_RUNTIME_DIR:-/run/user/$(${coreutils}/id -u)}"
    WAYLAND_SOCK="$XDR_VAL/$WAYLAND_DISPLAY_VAL"

    SWAYSOCK_EXISTS=false
    if [ -n "$SWAYSOCK_VAL" ] && [ -S "$SWAYSOCK_VAL" ]; then SWAYSOCK_EXISTS=true; fi

    WAYLAND_SOCK_EXISTS=false
    if [ -n "$WAYLAND_DISPLAY_VAL" ] && [ -S "$WAYLAND_SOCK" ]; then WAYLAND_SOCK_EXISTS=true; fi

    # #region agent log
    ${writeLog} "H_PORTAL_GTK" "user/wm/sway/debug/relog-instrumentation.nix:portal-gtk-prestart-debug:prestart" \
      "xdg-desktop-portal-gtk ExecStartPre snapshot" \
      "{\"ts\":$TS,\"env_exists\":$ENV_EXISTS,\"display\":\"''${DISPLAY:-}\",\"gdk_backend\":\"''${GDK_BACKEND:-}\",\"wayland_display\":\"$WAYLAND_DISPLAY_VAL\",\"wayland_sock\":\"$WAYLAND_SOCK\",\"wayland_sock_exists\":$WAYLAND_SOCK_EXISTS,\"swaysock_set\":$([ -n \"$SWAYSOCK_VAL\" ] && echo true || echo false),\"swaysock_exists\":$SWAYSOCK_EXISTS,\"xdg_current_desktop\":\"''${XDG_CURRENT_DESKTOP:-}\"}"
    # #endregion agent log
  '';
in
{
  inherit
    write-sway-portal-env-debug
    write-sway-session-env-debug
    sway-session-start-debug
    waybar-prestart-debug
    portal-gtk-prestart-debug;
}


