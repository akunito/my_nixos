{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  systemSettings,
  ...
}:

let
  cfgEnable = (systemSettings.waypaperEnable or false);

  # awww doesn't exist on nixos-25.11 — pin to unstable.
  SWWW = lib.getExe pkgs-unstable.awww;
  SWWW_DAEMON = lib.getExe' pkgs-unstable.awww "awww-daemon";
  SWAYMSG = lib.getExe' pkgs.sway "swaymsg";

  # Waypaper only knows the backend names hardcoded in its own BACKEND_OPTIONS
  # list ("none", "swaybg", "swww", "feh", ...) and detects each one with
  # `shutil.which(<name>)`. We drive the awww fork, whose binaries are named
  # awww/awww-daemon, so Waypaper never finds a Wayland backend: it rewrites the
  # config to the last backend it *did* find — `feh`, pulled in unconditionally
  # by stylix — and then silently no-ops, because feh is an X11 tool.
  # These shims give Waypaper the binary names it looks for.
  swww-shim = pkgs.writeShellScriptBin "swww" ''
    exec ${SWWW} "$@"
  '';

  # Waypaper runs `pgrep swww-daemon` and spawns `swww-daemon` when that finds
  # nothing. Ours is awww-daemon owned by swww-daemon.service — and the process
  # name is the `.awww-daemon-wr` nix wrapper, so Waypaper's pgrep can never
  # match it. Launching a real second daemon is destructive: awww evicts the
  # running instance, which kills the service and leaves no wallpaper behind
  # once Waypaper's short-lived child exits. Defer to systemd instead.
  swww-daemon-shim = pkgs.writeShellScriptBin "swww-daemon" ''
    SYSTEMCTL='${pkgs.systemd}/bin/systemctl'
    if "$SYSTEMCTL" --user --quiet is-active swww-daemon.service 2>/dev/null; then
      exit 0
    fi
    if "$SYSTEMCTL" --user start swww-daemon.service >/dev/null 2>&1; then
      exit 0
    fi
    exec ${SWWW_DAEMON} "$@"
  '';

  waypaperConfigFile = "${config.xdg.configHome}/waypaper/config.ini";
  awwwCacheDir = "${config.xdg.cacheHome}/awww";
  fallbackImage = if systemSettings.stylixEnable == true then config.stylix.image else null;

  JQ = lib.getExe pkgs.jq;

  # Watch for hot-plugged monitors and trigger wallpaper restore.
  # Subscribes to Sway output events, debounces (2s) for docks that add multiple outputs at once.
  waypaper-output-watch = pkgs.writeShellScriptBin "waypaper-output-watch" ''
    #!/bin/sh
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils ]}:$PATH"

    SWAYMSG='${SWAYMSG}'
    JQ='${JQ}'

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"

    if [ -r "$ENV_FILE" ]; then
      # shellcheck disable=SC1090
      . "$ENV_FILE"
    fi

    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
      if [ -n "$CAND" ] && [ -S "$CAND" ]; then
        export SWAYSOCK="$CAND"
      fi
    fi

    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      echo "waypaper-output-watch: no SWAYSOCK found; exiting" >&2
      exit 1
    fi

    echo "waypaper-output-watch: listening for output events on $SWAYSOCK" >&2

    LAST_TRIGGER=0

    "$SWAYMSG" -t subscribe '["output"]' -m | while read -r event; do
      CHANGE="$(echo "$event" | "$JQ" -r '.change // empty' 2>/dev/null || true)"
      if [ "$CHANGE" = "new" ]; then
        NOW="$(date +%s)"
        ELAPSED=$((NOW - LAST_TRIGGER))
        if [ "$ELAPSED" -ge 2 ]; then
          echo "waypaper-output-watch: new output detected, restoring wallpaper in 2s" >&2
          sleep 2
          ${pkgs.systemd}/bin/systemctl --user start waypaper-restore.service >/dev/null 2>&1 || true
          LAST_TRIGGER="$(date +%s)"
        fi
      fi
    done
  '';

  # Robust waypaper restore: resolves SWAYSOCK, waits for Sway outputs + swww-daemon,
  # generates Stylix fallback config on first run, then calls `waypaper --restore`.
  waypaper-restore-wrapper = pkgs.writeShellScriptBin "waypaper-restore-wrapper" ''
    #!/bin/sh
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.waypaper pkgs-unstable.awww pkgs.procps swww-shim swww-daemon-shim pkgs.gnused pkgs.gnugrep ]}:$PATH"

    SWAYMSG='${SWAYMSG}'
    SWWW='${SWWW}'
    CONFIG_FILE='${waypaperConfigFile}'

    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"

    if [ -r "$ENV_FILE" ]; then
      # shellcheck disable=SC1090
      . "$ENV_FILE"
    fi

    # Resolve a live SWAYSOCK (or bail out quietly if not in a Sway session).
    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
      if [ -n "$CAND" ] && [ -S "$CAND" ]; then
        export SWAYSOCK="$CAND"
      fi
    fi

    if [ -z "''${SWAYSOCK:-}" ] || [ ! -S "''${SWAYSOCK:-}" ]; then
      echo "waypaper-restore: no SWAYSOCK found; skipping" >&2
      exit 0
    fi

    # Wait for Sway outputs to be ready (up to ~30s).
    i=0
    while [ "$i" -lt 120 ]; do
      if "$SWAYMSG" -t get_outputs -r >/dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
      sleep 0.25
    done
    if [ "$i" -ge 120 ]; then
      echo "waypaper-restore: swaymsg not responsive yet; skipping" >&2
      exit 0
    fi

    # Wait for swww-daemon readiness via `swww query` (up to ~30s).
    i=0
    while [ "$i" -lt 120 ]; do
      if "$SWWW" query >/dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
      sleep 0.25
    done
    if [ "$i" -ge 120 ]; then
      echo "waypaper-restore: swww-daemon not ready (query failed); skipping" >&2
      exit 0
    fi

    # First-run fallback: generate default Waypaper config from Stylix image.
    if [ ! -f "$CONFIG_FILE" ]; then
      ${lib.optionalString (fallbackImage != null) ''
      echo "waypaper-restore: no config found, generating default from Stylix image" >&2
      mkdir -p "$(dirname "$CONFIG_FILE")"
      cat > "$CONFIG_FILE" << 'INIEOF'
[Settings]
folder = /nix/store
wallpaper = ${fallbackImage}
backend = swww
monitors = All
fill = fill
sort = name
color = #ffffff
subfolders = False
number_of_columns = 3
post_command =
swww_transition_type = any
swww_transition_step = 90
swww_transition_angle = 0
swww_transition_duration = 2
swww_transition_fps = 60
INIEOF
      ''}
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
      echo "waypaper-restore: no config file and no Stylix fallback; skipping" >&2
      exit 0
    fi

    # Self-heal the backend. Waypaper silently rewrites `backend` whenever the
    # configured value isn't one it recognises, and on a Wayland session that
    # lands on feh, which sets nothing at all. Pin it back to the swww shim.
    CURRENT_BACKEND="$(sed -n 's/^backend *= *//p' "$CONFIG_FILE" | head -n1)"
    if [ "$CURRENT_BACKEND" != "swww" ]; then
      echo "waypaper-restore: backend was '$CURRENT_BACKEND', forcing swww" >&2
      if grep -q '^backend *=' "$CONFIG_FILE"; then
        sed -i 's/^backend *=.*/backend = swww/' "$CONFIG_FILE"
      else
        printf '\nbackend = swww\n' >> "$CONFIG_FILE"
      fi
    fi

    exec waypaper --restore
  '';

  # Force a *full* re-upload of the wallpaper.
  #
  # Why this exists at all: after a suspend/resume cycle the wallpaper comes
  # back peppered with corrupted tiles — ~12x6 px black blocks holding a few
  # saturated pixels, scattered over both outputs (487 of them measured on DESK
  # 2026-09-09). They are GPU-side: the daemon's CPU buffers, read straight out
  # of `/proc/$(pidof awww-daemon)/fd/N` (the `memfd:awww-ipc` whose size is
  # width*height*4), are clean at exactly those coordinates.
  #
  # `waypaper --restore` does NOT clear them. Measured: 487 specks before,
  # byte-identical 487 specks after. awww/swww is a diff-based protocol — it
  # uploads only the pixels that changed between the displayed image and the
  # new one — so re-sending the image that is *already displayed* changes
  # nothing and never touches the corrupted texture. Only content that actually
  # differs forces a full re-upload, which is why picking a different wallpaper
  # in the Waypaper GUI has been the only thing that fixed it by hand.
  #
  # So: paint a solid colour (a guaranteed full-frame change), then put the
  # wallpaper back. `awww clear` does not touch awww's own cache — verified —
  # so `awww restore` afterwards reinstates the exact same image, resize mode
  # and filter, without going through Waypaper's ~0.5s Python startup. The
  # visible cost is 2-3 frames of black on whatever wallpaper is not covered
  # by a window.
  waypaper-force-refresh = pkgs.writeShellScriptBin "waypaper-force-refresh" ''
    #!/bin/sh
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.findutils ]}:$PATH"

    SWWW='${SWWW}'
    CACHE_DIR='${awwwCacheDir}'

    # The awww client talks to the daemon over its own socket in
    # XDG_RUNTIME_DIR, so no SWAYSOCK/WAYLAND_DISPLAY is needed here.
    if ! "$SWWW" query >/dev/null 2>&1; then
      echo "waypaper-refresh: awww-daemon not running; skipping" >&2
      exit 0
    fi

    # `awww restore` replays the daemon's cache. With no cache there is nothing
    # to put back after the clear, so take the slow path instead of blanking
    # the desktop.
    if [ -z "$(find "$CACHE_DIR" -type f -print -quit 2>/dev/null)" ]; then
      echo "waypaper-refresh: no awww cache; falling back to full restore" >&2
      exec ${waypaper-restore-wrapper}/bin/waypaper-restore-wrapper
    fi

    "$SWWW" clear 000000

    if ! "$SWWW" restore; then
      echo "waypaper-refresh: restore from cache failed; falling back" >&2
      exec ${waypaper-restore-wrapper}/bin/waypaper-restore-wrapper
    fi
  '';
in
{
  config = lib.mkIf cfgEnable {
    # Install Waypaper GUI package
    home.packages = [
      pkgs.waypaper # GUI frontend for swww/swaybg wallpaper backends
      # Must be on the session PATH too: the GUI (Hyper+Shift+B) shells out to
      # `swww` itself, not through waypaper-restore-wrapper.
      swww-shim
      swww-daemon-shim
      # Manual escape hatch, same thing Hyper+F5 and the post-resume repair run.
      waypaper-force-refresh
    ];

    # Desktop entry for application launcher
    xdg.desktopEntries.waypaper = {
      name = "Waypaper";
      genericName = "Wallpaper Manager";
      comment = "GUI wallpaper manager for Wayland compositors (swww/swaybg)";
      exec = "waypaper";
      terminal = false;
      categories = [ "Settings" "DesktopSettings" "Utility" ];
      icon = "preferences-desktop-wallpaper";
    };

    # Long-running watcher: triggers wallpaper restore when a new monitor is hot-plugged
    systemd.user.services.waypaper-output-watch = {
      Unit = {
        Description = "Watch for new Sway outputs and restore wallpaper";
        PartOf = [ "sway-session.target" ];
        After = [ "swww-daemon.service" "sway-session.target" "graphical-session.target" ];
        # Prevent sd-switch from restarting during rebuilds
        X-RestartIfChanged = "false";
      };

      Service = {
        Type = "simple";
        ExecStart = "${waypaper-output-watch}/bin/waypaper-output-watch";
        Restart = "on-failure";
        RestartSec = "5s";
        EnvironmentFile = [ "-%t/sway-session.env" ];
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    # Systemd service for wallpaper restoration
    # Waits for swww-daemon + Sway outputs, generates Stylix fallback on first run
    systemd.user.services.waypaper-restore = {
      Unit = {
        Description = "Waypaper wallpaper restore (SwayFX)";
        PartOf = [ "sway-session.target" ];
        Requires = [ "swww-daemon.service" ];
        After = [ "swww-daemon.service" "sway-session.target" "graphical-session.target" ];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${waypaper-restore-wrapper}/bin/waypaper-restore-wrapper";
        EnvironmentFile = [ "-%t/sway-session.env" ];
      };

      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };

    # On-demand full re-upload. Not wanted by any target: it is triggered by the
    # post-resume repair and by the manual wallpaper-refresh keybinding, both in
    # the Sway module. Deliberately NOT used for session start or HM activation
    # — those have nothing on screen to repair, and would only pay the flash.
    systemd.user.services.waypaper-refresh = {
      Unit = {
        Description = "Force a full wallpaper re-upload (clears GPU texture corruption)";
        PartOf = [ "sway-session.target" ];
        After = [ "swww-daemon.service" "graphical-session.target" ];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${waypaper-force-refresh}/bin/waypaper-force-refresh";
        EnvironmentFile = [ "-%t/sway-session.env" ];
      };
    };

    # Home-Manager activation hook: re-trigger wallpaper restore after HM switch.
    # Matches swww.nix pattern: runs after reloadSystemd, checks for live Sway IPC socket.
    home.activation.waypaperRestore = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      ENV_FILE="$RUNTIME_DIR/sway-session.env"
      if [ -r "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        . "$ENV_FILE"
      fi
      if [ -n "''${SWAYSOCK:-}" ] && [ -S "''${SWAYSOCK:-}" ]; then
        sleep 1
        ${pkgs.systemd}/bin/systemctl --user start waypaper-restore.service >/dev/null 2>&1 || true
      else
        CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
        if [ -n "$CAND" ] && [ -S "$CAND" ]; then
          sleep 1
          ${pkgs.systemd}/bin/systemctl --user start waypaper-restore.service >/dev/null 2>&1 || true
        fi
      fi
    '';
  };
}
