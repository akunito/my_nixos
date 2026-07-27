{ config, lib, pkgs, systemSettings, ... }:

let
  # Monitor-hotplug snapshot/restore (DESK): keep workspaces, focus and
  # floating windows where they were when monitors are switched off and on.
  # See scripts/sway-snapshot-daemon.sh and scripts/sway-hotplug-restore.sh.
  enabled = systemSettings.swayHotplugRestoreEnable or false;

  # Hardware-ID -> swaysome group pinning consumed by the restore script's
  # group-0 orphan migration (same data drives the declarative
  # `workspace N output` lines in swayfx-config.nix).
  pins = systemSettings.swayWorkspaceOutputPins or [ ];
  pinsConf = lib.concatMapStrings (p: "${toString p.group}|${p.criteria}\n") pins;

  sway-snapshot-daemon = pkgs.writeShellApplication {
    name = "sway-snapshot-daemon";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      sway
    ];
    text = builtins.readFile ./scripts/sway-snapshot-daemon.sh;
  };
in
{
  config = lib.mkIf enabled {
    home.file.".config/sway/scripts/sway-hotplug-restore.sh" = {
      source = ./scripts/sway-hotplug-restore.sh;
      executable = true;
    };

    home.file.".config/sway/workspace-output-pins.conf".text = pinsConf;

    systemd.user.services.sway-snapshot-daemon = {
      Unit = {
        Description = "Snapshot workspace/floating state per monitor set (hotplug restore)";
        PartOf = [ "sway-session.target" ];
        After = [ "sway-session.target" ];
      };
      Service = {
        Type = "simple";
        EnvironmentFile = "-%t/sway-session.env";
        ExecStart = "${sway-snapshot-daemon}/bin/sway-snapshot-daemon";
        Restart = "on-failure";
        RestartSec = "3";
      };
      Install = {
        WantedBy = [ "sway-session.target" ];
      };
    };
  };
}
