{ config, lib, pkgs, systemSettings, ... }:

let
  swaybgplusPkg = pkgs.callPackage ../../pkgs/swaybgplus.nix { };
  swaybgplusWallpaperEnsure = pkgs.writeShellScriptBin "swaybgplus-wallpaper-ensure" ''
    #!/bin/sh
    set -eu

    CFG="${config.xdg.stateHome}/swaybgplus/backgrounds/current_config.json"
    # Ensure required helpers are available even in a minimal systemd --user environment.
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.sway pkgs.swaybg swaybgplusPkg ]}:$PATH"

    # Ensure we have a live SWAYSOCK; on some startups the environment file may not be present yet.
    # We try (in order):
    # - %t/sway-session.env (if present)
    # - autodetect newest sway-ipc socket
    # - if none, keep waiting (cold boot race) but never fail the session
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"

    wait_for_sway_ipc() {
      i=0
      while [ "$i" -lt 240 ]; do
        # The env file may be created after we start; re-source it while waiting.
        if [ -r "$ENV_FILE" ]; then
          # shellcheck disable=SC1090
          . "$ENV_FILE"
        fi

        if [ -n "''${SWAYSOCK:-}" ] && [ -S "''${SWAYSOCK:-}" ]; then
          return 0
        fi

        CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
        if [ -n "$CAND" ] && [ -S "$CAND" ]; then
          SWAYSOCK="$CAND"
          export SWAYSOCK
          return 0
        fi

        i=$((i + 1))
        sleep 0.25
      done
      return 1
    }

    wait_for_swaymsg() {
      i=0
      while [ "$i" -lt 120 ]; do
        if swaymsg -t get_outputs -r >/dev/null 2>&1; then
          return 0
        fi
        i=$((i + 1))
        sleep 0.25
      done
      return 1
    }

    last_mtime=""
    while :; do
      # If there is no saved wallpaper config yet, do nothing (but keep running).
      if [ ! -r "$CFG" ]; then
        sleep 2
        continue
      fi

      # Make sure Sway IPC is actually live.
      if ! wait_for_sway_ipc; then
        sleep 1
        continue
      fi
      if ! wait_for_swaymsg; then
        sleep 1
        continue
      fi

      mtime="$(stat -c %Y "$CFG" 2>/dev/null || echo '')"
      has_swaybg=false
      if pgrep -x swaybg >/dev/null 2>&1; then
        has_swaybg=true
      fi

      # Re-apply on either:
      # - config change
      # - swaybg got killed (common during user systemd reloads / HM switch)
      if [ "$mtime" != "$last_mtime" ] || [ "$has_swaybg" != "true" ]; then
        echo "swaybgplus: ensuring wallpaper (cfg_mtime=$mtime, had_swaybg=$has_swaybg)" >&2
        "${swaybgplusPkg}/bin/swaybgplus" --restore || true
        last_mtime="$mtime"
      fi

      sleep 2
    done
  '';
in
{
  home.packages = lib.mkIf (systemSettings.swaybgPlusEnable or false) [
    swaybgplusPkg
    pkgs.swaybg
  ];

  # Make it easy to launch from rofi/fuzzel/drun
  xdg.desktopEntries.swaybgplus = lib.mkIf (systemSettings.swaybgPlusEnable or false) {
    name = "SwayBG+";
    comment = "Advanced multi-monitor wallpaper manager for Sway (GUI)";
    exec = "${swaybgplusPkg}/bin/swaybgplus-gui";
    terminal = false;
    categories = [ "Settings" ];
  };

  # Restore saved wallpaper configuration when a Sway session starts.
  # This is inert outside Sway because it only binds to sway-session.target.
  systemd.user.services.swaybgplus-restore = lib.mkIf (systemSettings.swaybgPlusEnable or false) {
    Unit = {
      Description = "SwayBG+ ensure wallpapers (self-heals across HM rebuilds + reboot)";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${swaybgplusWallpaperEnsure}/bin/swaybgplus-wallpaper-ensure";
      Restart = "always";
      RestartSec = "2s";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };
}


