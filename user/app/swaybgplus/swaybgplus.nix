# ============================================================================
# DEPRECATED: SwayBG+ Wallpaper Manager
# ============================================================================
# This module is deprecated in favor of Waypaper (user/app/waypaper/waypaper.nix).
# Use waypaperEnable instead of swaybgPlusEnable in your profile configuration.
#
# Reason for deprecation:
# - SwayBG+ has documentation inaccuracies (claims swww but uses swaybg)
# - Waypaper is actively maintained and better integrated with swww
# - Waypaper is lighter (315 KB) and simpler to maintain
#
# Migration:
# - Set waypaperEnable = true in your profile
# - Keep swwwEnable = true (Waypaper uses swww backend)
# - Remove swaybgPlusEnable = false (it's now default)
#
# This module is kept for reference and backward compatibility.
# ============================================================================

{ config, lib, pkgs, systemSettings, ... }:

let
  swaybgplusPkg = pkgs.callPackage ../../pkgs/swaybgplus.nix { };
  swaybgplusRestoreWrapper = pkgs.writeShellScriptBin "swaybgplus-restore-wrapper" ''
    #!/bin/sh
    set -eu

    CFG="${config.xdg.stateHome}/swaybgplus/backgrounds/current_config.json"
    # If there is no saved wallpaper config yet, do nothing and succeed.
    if [ ! -r "$CFG" ]; then
      exit 0
    fi

    # Ensure required helpers are available even in a minimal systemd --user environment.
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.sway pkgs.swaybg swaybgplusPkg ]}:$PATH"

    # Ensure we have a live SWAYSOCK; on some startups the environment file may not be present yet.
    # We try (in order):
    # - %t/sway-session.env (if present)
    # - autodetect newest sway-ipc socket
    # - if none, wait briefly (cold boot race), then exit successfully (don't break session)
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"

    wait_for_sway_ipc() {
      i=0
      while [ "$i" -lt 240 ]; do  # up to ~60s
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
      while [ "$i" -lt 120 ]; do  # up to ~30s
        if swaymsg -t get_outputs -r >/dev/null 2>&1; then
          return 0
        fi
        i=$((i + 1))
        sleep 0.25
      done
      return 1
    }

    if ! wait_for_sway_ipc; then
      echo "swaybgplus-restore: no live SWAYSOCK after waiting; skipping restore" >&2
      exit 0
    fi
    if ! wait_for_swaymsg; then
      echo "swaybgplus-restore: swaymsg not responsive yet; skipping restore" >&2
      exit 0
    fi

    exec "${swaybgplusPkg}/bin/swaybgplus" --restore
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
      Description = "SwayBG+ restore wallpapers";
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${swaybgplusRestoreWrapper}/bin/swaybgplus-restore-wrapper";
      EnvironmentFile = [ "-%t/sway-session.env" ];
    };
    Install = {
      WantedBy = [ "sway-session.target" ];
    };
  };

  # Home-Manager activation reloads systemd --user and can kill background processes like swaybg.
  # Re-run wallpaper restore once after HM activation when (and only when) we're in a real Sway session.
  home.activation.swaybgplusRestoreAfterSwitch = lib.mkIf (systemSettings.swaybgPlusEnable or false) (
    lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      ENV_FILE="$RUNTIME_DIR/sway-session.env"
      if [ -r "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        . "$ENV_FILE"
      fi

      # Only trigger restore when we're in a real Sway session (live IPC socket).
      if [ -n "''${SWAYSOCK:-}" ] && [ -S "''${SWAYSOCK:-}" ]; then
        ${pkgs.systemd}/bin/systemctl --user start swaybgplus-restore.service >/dev/null 2>&1 || true
      else
        CAND="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
        if [ -n "$CAND" ] && [ -S "$CAND" ]; then
          ${pkgs.systemd}/bin/systemctl --user start swaybgplus-restore.service >/dev/null 2>&1 || true
        fi
      fi
    ''
  );
}


