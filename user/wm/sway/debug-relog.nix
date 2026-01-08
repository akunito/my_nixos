{ pkgs
, lib
, systemSettings
, writeDebugLog
, writeSwaySessionEnv
, ...
}:

let
  # Keep logging implementation centralized via existing helper script.
  # NOTE: writeDebugLog is pkgs.writeShellScriptBin "write-debug-log" from debug-qt5ct.nix
  writeLog = "${writeDebugLog}/bin/write-debug-log";

  # Debug wrapper: write the session env file + log what was captured.
  write-sway-session-env-debug = pkgs.writeShellScriptBin "write-sway-session-env-debug" ''
    #!/bin/sh
    TS="$(date +%s%3N 2>/dev/null || date +%s000)"
    ENV_FILE="/run/user/$(id -u)/sway-session.env"

    # #region agent log
    ${writeLog} "H_ENV" "write-sway-session-env-debug:entry" "About to write %t/sway-session.env" \
      "{\"ts\":$TS,\"xdr\":\"''${XDG_RUNTIME_DIR:-}\",\"wayland_display\":\"''${WAYLAND_DISPLAY:-}\",\"swaysock\":\"''${SWAYSOCK:-}\",\"env_file\":\"$ENV_FILE\"}"
    # #endregion

    "${writeSwaySessionEnv}/bin/write-sway-session-env" >/dev/null 2>&1 || true

    # #region agent log
    ENV_EXISTS=false
    ENV_SIZE=0
    ENV_MTIME=0
    if [ -f "$ENV_FILE" ]; then
      ENV_EXISTS=true
      ENV_SIZE="$(stat -c '%s' "$ENV_FILE" 2>/dev/null || echo 0)"
      ENV_MTIME="$(stat -c '%Y' "$ENV_FILE" 2>/dev/null || echo 0)"
    fi
    ${writeLog} "H_ENV" "write-sway-session-env-debug:exit" "Finished writing %t/sway-session.env" \
      "{\"ts\":$TS,\"env_exists\":$ENV_EXISTS,\"env_size\":$ENV_SIZE,\"env_mtime\":$ENV_MTIME}"
    # #endregion
  '';

  # Debug wrapper: start sway-session.target and measure any blocking time in systemctl.
  sway-session-start-debug = pkgs.writeShellScriptBin "sway-session-start-debug" ''
    #!/bin/sh
    TS_START="$(date +%s%3N 2>/dev/null || date +%s000)"

    GS_ACTIVE="$(systemctl --user show -p ActiveState --value graphical-session.target 2>/dev/null || echo "unknown")"
    GS_SUB="$(systemctl --user show -p SubState --value graphical-session.target 2>/dev/null || echo "unknown")"

    # #region agent log
    ${writeLog} "H_SYSTEMD" "sway-session-start-debug:pre_start" "About to start sway-session.target" \
      "{\"ts\":$TS_START,\"graphical_session_active\":\"$GS_ACTIVE\",\"graphical_session_sub\":\"$GS_SUB\"}"
    # #endregion

    systemctl --user start sway-session.target >/dev/null 2>&1
    RC="$?"

    TS_END="$(date +%s%3N 2>/dev/null || date +%s000)"
    DURATION_MS=$((TS_END - TS_START))

    SS_ACTIVE="$(systemctl --user show -p ActiveState --value sway-session.target 2>/dev/null || echo "unknown")"
    SS_SUB="$(systemctl --user show -p SubState --value sway-session.target 2>/dev/null || echo "unknown")"
    WB_ACTIVE="$(systemctl --user show -p ActiveState --value waybar.service 2>/dev/null || echo "unknown")"
    WB_SUB="$(systemctl --user show -p SubState --value waybar.service 2>/dev/null || echo "unknown")"

    # #region agent log
    ${writeLog} "H_SYSTEMD" "sway-session-start-debug:post_start" "Started sway-session.target (systemctl returned)" \
      "{\"ts\":$TS_END,\"rc\":$RC,\"duration_ms\":$DURATION_MS,\"sway_session_active\":\"$SS_ACTIVE\",\"sway_session_sub\":\"$SS_SUB\",\"waybar_active\":\"$WB_ACTIVE\",\"waybar_sub\":\"$WB_SUB\"}"
    # #endregion
  '';

  # ExecStartPre hook for waybar: record whether env + SWAYSOCK are valid right before launch.
  waybar-prestart-debug = pkgs.writeShellScriptBin "waybar-prestart-debug" ''
    #!/bin/sh
    TS="$(date +%s%3N 2>/dev/null || date +%s000)"
    ENV_FILE="/run/user/$(id -u)/sway-session.env"

    SWAYSOCK_VAL="''${SWAYSOCK:-}"
    WAYLAND_DISPLAY_VAL="''${WAYLAND_DISPLAY:-}"

    ENV_EXISTS=false
    if [ -f "$ENV_FILE" ]; then ENV_EXISTS=true; fi

    SWAYSOCK_EXISTS=false
    if [ -n "$SWAYSOCK_VAL" ] && [ -S "$SWAYSOCK_VAL" ]; then SWAYSOCK_EXISTS=true; fi

    # #region agent log
    ${writeLog} "H_WAYBAR" "waybar-prestart-debug:prestart" "Waybar ExecStartPre snapshot" \
      "{\"ts\":$TS,\"env_exists\":$ENV_EXISTS,\"swaysock_set\":$([ -n "$SWAYSOCK_VAL" ] && echo true || echo false),\"swaysock_exists\":$SWAYSOCK_EXISTS,\"wayland_display_set\":$([ -n "$WAYLAND_DISPLAY_VAL" ] && echo true || echo false)}"
    # #endregion
  '';
in
{
  inherit
    write-sway-session-env-debug
    sway-session-start-debug
    waybar-prestart-debug;
}


