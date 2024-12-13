{ lib, pkgs, authorizedKeys ? [], ... }:

{
  # users.users.restic = {
  #   isNormalUser = true;
  # };

  # security.wrappers.restic = {
  #   source = "${pkgs.restic.out}/bin/restic";
  #   owner = "restic";
  #   group = "users";
  #   permissions = "u=rwx,g=,o=";
  #   capabilities = "cap_dac_read_search=+ep";
  # };

  # # Systemd service to execute sh script /home/aga/myScripts/agalaptop_backup.sh 
  # # User as aga
  # # Every 6 hours
  # # The script includes sudo commands inside so password will be asked
  # systemd.services.agalaptop_backup = {
  #   description = "Backup agalaptop";
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "simple";
  #     ExecStart = "~/.nix-profile/bin/sh /home/aga/myScripts/agalaptop_backup.sh";
  #     Restart = "on-failure";
  #     RestartSec = "6h";
  #     User = "aga";
  #   };
  # };
}
