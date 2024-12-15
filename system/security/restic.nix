{ lib, userSettings, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  # ====================== Wrappers ======================
  # Create restic user
  users.users.restic = lib.mkIf (systemSettings.resticWrapper == true) {
    isNormalUser = true;
  };
  # Wrapper for restic
  security.wrappers.restic = lib.mkIf (systemSettings.resticWrapper == true) {
    source = "/run/current-system/sw/bin/restic";
    owner = userSettings.username; # Sets the owner of the restic binary (see below u=rwx)
    group = "wheel";
    permissions = "u=rwx,g=,o=";
    capabilities = "cap_dac_read_search=+ep";
  };

  # Create restic user
  users.users.rsync = lib.mkIf (systemSettings.rsyncWrapper == true) {
    isNormalUser = true;
  };
  # Wrapper for rsync
  security.wrappers.rsync = lib.mkIf (systemSettings.rsyncWrapper == true) {
    source = "/run/current-system/sw/bin/rsync";
    owner = userSettings.username;
    group = "wheel";
    permissions = "u=rwx,g=,o=";
    capabilities = "cap_dac_read_search=+ep";
  };


  # ====================== Local Backup settings ======================
  # Systemd service to execute sh script
  # Main user | Every 6 hours | Script includes wrapper for restic (config on sudo.nix)
  systemd.services.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.homeBackupExecStart;
      User = systemSettings.homeBackupUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
    unitConfig = lib.mkIf (systemSettings.homeBackupEnable == true) { # Call next service on success
      OnSuccess = systemSettings.homeBackupCallNext;
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


  # ====================== Remote Backup settings ======================
  # Systemd service to run after home_backup
  systemd.services.remote_backup = lib.mkIf (systemSettings.remoteBackupEnable == true) {
    description = systemSettings.remoteBackupDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.remoteBackupExecStart;
      User = systemSettings.remoteBackupUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
  };
}
