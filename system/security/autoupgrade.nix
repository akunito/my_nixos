{ pkgs, systemSettings, lib, inputs, ... }:

{
  # ====================== Auto System Update ======================
  systemd.services.autoSystemUpdate = lib.mkIf (systemSettings.autoSystemUpdateEnable == true) {
    description = systemSettings.autoSystemUpdateDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = let
        scriptDir = "/home/${systemSettings.autoUserUpdateUser}/.dotfiles";
        restartDocker = if systemSettings.autoUpgradeRestartDocker or false then "true" else "false";
      in "${systemSettings.autoSystemUpdateExecStart} ${scriptDir} ${restartDocker}";
      User = systemSettings.autoSystemUpdateUser;
      Environment = [
        "PATH=/run/current-system/sw/bin:/usr/bin:/bin"
        "HOME=/root"
      ];
      StandardOutput = "journal";
      StandardError = "journal";
    };
    unitConfig = {
      OnSuccess = systemSettings.autoSystemUpdateCallNext;
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  systemd.timers.autoSystemUpdate = lib.mkIf (systemSettings.autoSystemUpdateEnable == true) {
    description = systemSettings.autoSystemUpdateTimerDescription;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = systemSettings.autoSystemUpdateOnCalendar;
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # ====================== Auto User Update (Home-Manager) ======================
  systemd.services.autoUserUpdate = lib.mkIf (systemSettings.autoUserUpdateEnable == true) {
    description = systemSettings.autoUserUpdateDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = let
        scriptDir = "/home/${systemSettings.autoUserUpdateUser}/.dotfiles";
        hmBranch = systemSettings.autoUserUpdateBranch or "master";
      in "${systemSettings.autoUserUpdateExecStart} ${scriptDir} ${hmBranch}";
      User = systemSettings.autoUserUpdateUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
}
