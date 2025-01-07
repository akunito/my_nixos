{ pkgs, systemSettings, lib, inputs, ... }: 

{
  # ====================== Auto System Update ======================
  systemd.services.autoSystemUpdate = lib.mkIf (systemSettings.autoSystemUpdateEnable == true) {
    description = systemSettings.autoSystemUpdateDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.autoSystemUpdateExecStart;
      User = systemSettings.autoSystemUpdateUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
    unitConfig = { # Call next service on success
      OnSuccess = systemSettings.autoSystemUpdateCallNext;
    };
  };
  systemd.timers.autoSystemUpdate = lib.mkIf (systemSettings.autoSystemUpdateEnable == true) {
    description = systemSettings.autoSystemUpdateTimerDescription;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = systemSettings.autoSystemUpdateOnCalendar; 
      Persistent = true;
    };
  };

  # ====================== Auto User Update ======================
  systemd.services.autoUserUpdate = lib.mkIf (systemSettings.autoUserUpdateEnable == true) {
    description = systemSettings.autoUserUpdateDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.autoUserUpdateExecStart;
      User = systemSettings.autoUserUpdateUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
  };
}

