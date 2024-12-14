{ lib, userSettings, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  # Create restic user
  users.users.restic = {
    isNormalUser = true;
  };
  # Wrapper for restic
  security.wrappers.restic = {
    source = "/run/current-system/sw/bin/restic";
    owner = userSettings.username; # Sets the owner of the restic binary (rwx)
    group = "wheel"; # Sets the group of the restic binary (none)
    permissions = "u=rwx,g=,o="; # Permissions of the restic binary
    capabilities = "cap_dac_read_search=+ep"; # Sets the capabilities of the restic binary
  };

  # Systemd service to execute sh script /home/aga/myScripts/agalaptop_backup.sh 
  # Main user | Every 6 hours | Script includes wrapper for restic (config on sudo.nix)
  systemd.services.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.homeBackupExecStart;
      User = systemSettings.homeBackupUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
  };
  systemd.timers.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupTimerDescription;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = systemSettings.homeBackupOnCalendar; # Every 6 hours
      Persistent = true;
    };
  };
}
