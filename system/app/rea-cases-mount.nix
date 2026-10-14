{ lib, userSettings, systemSettings, ... }:
# REA sandbox cases (AINF-408): ~/rea/cases is bind-mounted onto itself with
# noexec,nosuid,nodev. `docker run -v` cannot set those flags, but bind mounts made
# from here inherit them and a user namespace cannot clear them, so nothing a hostile
# target leaves in a case is ever executable on the host.
let
  enabled = systemSettings.reaSandboxEnable or false;
  user = userSettings.username;
  dir = "/home/${user}/rea/cases";
in
lib.mkIf enabled {
  # Activation runs before switch-to-configuration starts new mount units, and the
  # directory then persists on disk for later boots. (tmpfiles would order after
  # local-fs.target, which wants this mount: a cycle.)
  system.activationScripts.reaCasesDir = ''
    install -d -m 0755 -o ${user} -g users /home/${user}/rea ${dir}
  '';
  fileSystems.${dir} = {
    device = dir;
    fsType = "none";
    options = [ "bind" "noexec" "nosuid" "nodev" "nofail" ];
  };
}
