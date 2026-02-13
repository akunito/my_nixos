{
  config,
  pkgs,
  lib,
  systemSettings,
  ...
}:

let
  cfgEnable = (systemSettings.waypaperEnable or false);

  SWWW = lib.getExe pkgs.swww;
  SWAYMSG = lib.getExe' pkgs.sway "swaymsg";

  waypaperConfigFile = "${config.xdg.configHome}/waypaper/config.ini";
  fallbackImage = if systemSettings.stylixEnable == true then config.stylix.image else null;

  # Robust waypaper restore: resolves SWAYSOCK, waits for Sway outputs + swww-daemon,
  # generates Stylix fallback config on first run, then calls `waypaper --restore`.
  waypaper-restore-wrapper = pkgs.writeShellScriptBin "waypaper-restore-wrapper" ''
    #!/bin/sh
    set -eu

    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.waypaper ]}:$PATH"

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

    exec waypaper --restore
  '';
in
{
  config = lib.mkIf cfgEnable {
    # Install Waypaper GUI package
    home.packages = with pkgs; [
      waypaper # GUI frontend for swww/swaybg wallpaper backends
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
        ${pkgs.systemd}/bin/systemctl --user start waypaper-restore.service >/dev/null 2>&1 || true
      else
        CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
        if [ -n "$CAND" ] && [ -S "$CAND" ]; then
          ${pkgs.systemd}/bin/systemctl --user start waypaper-restore.service >/dev/null 2>&1 || true
        fi
      fi
    '';
  };
}
