{ config, lib, pkgs, systemSettings, ... }:

let
  cfgEnable = (systemSettings.swwwEnable or false);

  SWWW = lib.getExe pkgs.swww;
  JQ = lib.getExe pkgs.jq;
  SWAYMSG = lib.getExe' pkgs.sway "swaymsg";

  stateFile = "${config.xdg.stateHome}/swww/wallpaper.json";
  fallbackImage = if systemSettings.stylixEnable == true then config.stylix.image else null;

  swwwRestoreWrapper = pkgs.writeShellScriptBin "swww-restore-wrapper" ''
    #!/bin/sh
    set -eu

    # Systemd --user can provide a very minimal PATH on NixOS; make common tools explicit.
    export PATH="${lib.makeBinPath [ pkgs.coreutils ]}:$PATH"

    STATE_FILE='${stateFile}'
    SWWW='${SWWW}'
    JQ='${JQ}'
    SWAYMSG='${SWAYMSG}'

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"

    if [ -r "$ENV_FILE" ]; then
      # shellcheck disable=SC1090
      . "$ENV_FILE"
    fi

    # Resolve a live SWAYSOCK (or bail out quietly if we're not in a Sway session).
    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
      if [ -n "$CAND" ] && [ -S "$CAND" ]; then
        export SWAYSOCK="$CAND"
      fi
    fi

    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      exit 0
    fi

    # Wait for outputs to be ready.
    i=0
    while [ "$i" -lt 120 ]; do # up to ~30s
      if "$SWAYMSG" -t get_outputs -r >/dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
      sleep 0.25
    done
    if [ "$i" -ge 120 ]; then
      echo "swww-restore: swaymsg not responsive yet; skipping" >&2
      exit 0
    fi

    # Wait for swww-daemon readiness.
    #
    # Note: the socket name is compositor-dependent (often derived from WAYLAND_DISPLAY), so
    # checking a fixed path like `$XDG_RUNTIME_DIR/swww.socket` is not reliable. `swww query`
    # is the canonical readiness probe.
    i=0
    while [ "$i" -lt 120 ]; do # up to ~30s
      if "$SWWW" query >/dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
      sleep 0.25
    done
    if [ "$i" -ge 120 ]; then
      echo "swww-restore: swww-daemon not ready (query failed); skipping" >&2
      exit 0
    fi

    IMAGE=""
    RESIZE="crop"
    OUTPUTS=""

    if [ -r "$STATE_FILE" ]; then
      IMAGE="$("$JQ" -r '.image // empty' "$STATE_FILE" 2>/dev/null || true)"
      RESIZE="$("$JQ" -r '.resize // "crop"' "$STATE_FILE" 2>/dev/null || echo "crop")"
      OUTPUTS="$("$JQ" -r '.outputs // ""' "$STATE_FILE" 2>/dev/null || echo "")"
    fi

    # First-run fallback.
    if [ -z "$IMAGE" ]; then
      ${lib.optionalString (fallbackImage != null) ''
      IMAGE='${fallbackImage}'
      RESIZE="crop"
      OUTPUTS=""
      ''}
    fi

    if [ -z "$IMAGE" ]; then
      echo "swww-restore: no state file ($STATE_FILE) and no fallback image configured; skipping" >&2
      exit 0
    fi
    if [ ! -r "$IMAGE" ]; then
      echo "swww-restore: image not readable: $IMAGE; skipping" >&2
      exit 0
    fi

    # Apply wallpaper. Default: no visible transition/blink.
    OUT_FLAG=""
    if [ -n "$OUTPUTS" ]; then
      OUT_FLAG="--outputs $OUTPUTS"
    fi

    # shellcheck disable=SC2086
    exec "$SWWW" img $OUT_FLAG --resize "$RESIZE" --transition-type none --transition-step 255 "$IMAGE"
  '';

  swwwSet = pkgs.writeShellScriptBin "swww-set" ''
    #!/bin/sh
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils ]}:$PATH"

    JQ='${JQ}'

    IMAGE="''${1:-}"
    RESIZE="''${2:-crop}"
    OUTPUTS="''${3:-}"

    if [ -z "$IMAGE" ]; then
      echo "usage: swww-set /path/to/image [resize=crop|fit|stretch|no] [outputs=comma,separated]" >&2
      exit 2
    fi
    if [ ! -r "$IMAGE" ]; then
      echo "swww-set: image not readable: $IMAGE" >&2
      exit 1
    fi

    STATE_DIR="$(dirname '${stateFile}')"
    mkdir -p "$STATE_DIR"

    # Write state atomically.
    TMP="''${STATE_DIR}/.wallpaper.json.tmp"
    "$JQ" -n \
      --arg image "$IMAGE" \
      --arg resize "$RESIZE" \
      --arg outputs "$OUTPUTS" \
      '{image:$image, resize:$resize, outputs:$outputs}' >"$TMP"
    mv -f "$TMP" '${stateFile}'

    # Trigger restore once (safe/no-op outside Sway).
    ${pkgs.systemd}/bin/systemctl --user start swww-restore.service >/dev/null 2>&1 || true
  '';
in
{
  home.packages = lib.mkIf cfgEnable [
    pkgs.swww
    pkgs.jq
    swwwSet
  ];

  systemd.user.services.swww-daemon = lib.mkIf cfgEnable {
    Unit = {
      Description = "swww-daemon (wallpaper backend for SwayFX)";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.swww}/bin/swww-daemon";
      Restart = "on-failure";
      RestartSec = "1s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  systemd.user.services.swww-restore = lib.mkIf cfgEnable {
    Unit = {
      Description = "swww restore wallpaper (SwayFX)";
      PartOf = [ "sway-session.target" ];
      Requires = [ "swww-daemon.service" ];
      After = [ "swww-daemon.service" "sway-session.target" "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${swwwRestoreWrapper}/bin/swww-restore-wrapper";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Home-Manager activation can reload systemd --user and disrupt wallpaper processes.
  # Re-trigger restore once after reloadSystemd, but only if a real Sway IPC socket exists.
  home.activation.swwwRestoreAfterSwitch = lib.mkIf cfgEnable (lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"
    if [ -r "$ENV_FILE" ]; then
      # shellcheck disable=SC1090
      . "$ENV_FILE"
    fi
    if [ -n "''${SWAYSOCK:-}" ] && [ -S "''${SWAYSOCK:-}" ]; then
      ${pkgs.systemd}/bin/systemctl --user start swww-restore.service >/dev/null 2>&1 || true
    else
      CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
      if [ -n "$CAND" ] && [ -S "$CAND" ]; then
        ${pkgs.systemd}/bin/systemctl --user start swww-restore.service >/dev/null 2>&1 || true
      fi
    fi
  '');
}


