{ lib, pkgs, authorizedKeys ? [], ... }:

{
  users.users.restic = {
    isNormalUser = true;
  };

  security.wrappers.restic = {
    source = "/run/current-system/sw/bin/restic";
    owner = "aga";
    group = "wheel";
    permissions = "u=rwx,g=,o=";
    capabilities = "cap_dac_read_search=+ep";
  };

  # Systemd service to execute sh script /home/aga/myScripts/agalaptop_backup.sh 
  # User as aga
  # Every 6 hours
  # The script includes sudo commands inside so password will be asked
  systemd.services.agalaptop_backup = {
    description = "Backup agalaptop";
    serviceConfig = {
      Type = "simple";
      ExecStart = "/run/current-system/sw/bin/sh /home/aga/myScripts/agalaptop_backup.sh";
      User = "aga";
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
  };

  systemd.timers.agalaptop_backup = {
    description = "Timer for agalaptop_backup service";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 0/6:00:00"; # Every 6 hours
      Persistent = true;
    };
  };
}
