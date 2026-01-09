{ config, lib, pkgs, systemSettings, ... }:

let
  swaybgplusPkg = pkgs.callPackage ../../pkgs/swaybgplus.nix { };
  swaybgplusRestoreWrapper = pkgs.writeShellScriptBin "swaybgplus-restore-wrapper" ''
    #!/bin/sh
    set -eu

    # If there is no saved wallpaper config yet, do nothing and succeed.
    CFG="${config.xdg.stateHome}/swaybgplus/backgrounds/current_config.json"
    if [ ! -r "$CFG" ]; then
      exit 0
    fi

    # Ensure required helpers are available even in a minimal systemd --user environment.
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.procps pkgs.sway pkgs.swaybg swaybgplusPkg ]}:$PATH"

    # Ensure we have a live SWAYSOCK; on some startups the environment file may not be present yet.
    # We try (in order):
    # - %t/sway-session.env (if present)
    # - autodetect newest sway-ipc socket
    # - if none, exit successfully (not in Sway session)
    RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ENV_FILE="$RUNTIME_DIR/sway-session.env"
    if [ -r "$ENV_FILE" ]; then
      # shellcheck disable=SC1090
      . "$ENV_FILE"
    fi

    if [ -z "${SWAYSOCK:-}" ] || [ ! -S "${SWAYSOCK:-}" ]; then
      SWAYSOCK="$(ls -t "$RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -n1 || true)"
      export SWAYSOCK
    fi

    if [ -z "${SWAYSOCK:-}" ] || [ ! -S "${SWAYSOCK:-}" ]; then
      # Not a Sway session (or compositor not ready yet); don't fail the session.
      exit 0
    fi

    # Wait briefly for swaymsg to be responsive (outputs ready).
    i=0
    while [ "$i" -lt 40 ]; do
      if swaymsg -t get_outputs -r >/dev/null 2>&1; then
        break
      fi
      i=$((i + 1))
      sleep 0.25
    done

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
      After = [ "sway-session.target" ];
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
}


