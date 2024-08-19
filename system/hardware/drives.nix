{ config, pkgs, systemSettings, lib, ... }:

{ 
  # Enable SSH server to unlock LUKS drives on BOOT
  boot = lib.mkIf (systemSettings.bootSSH == true) {
    kernelParams = [ "ip=dhcp" ];
    initrd = {
      availableKernelModules = [ "r8169" ];
      systemd.users.root.shell = "/bin/cryptsetup-askpass";
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 22;
          authorizedKeys = systemSettings.authorizedKeys; # SSH keys
          hostKeys = systemSettings.hostKeys;
        };
      }; 
    };
  };

  # # Open DATA_4TB LUKS on Boot
  # boot.initrd.luks.devices."DATA_4TB" = {
  #   device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
  # };

  # # Open TimeShift LUKS on Boot
  # boot.initrd.luks.devices."TimeShift" = {
  #   device = "/dev/disk/by-uuid/04aaf88f-c0dd-40ad-be7e-85e29c0bd719";
  # };

  # # Open Machines LUKS on Boot
  # boot.initrd.luks.devices."Machines" = {
  #   device = "/dev/disk/by-uuid/452c53a6-0578-4c38-840d-87f1f3f34ddb";
  # };
    
}
