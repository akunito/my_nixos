{ config, pkgs, systemSettings, lib, ... }:

{ 
  boot = {
    # Enable SSH server to unlock LUKS drives on BOOT
    kernelParams = lib.mkIf (systemSettings.bootSSH == true) [ "ip=dhcp" ];
    initrd = {
      availableKernelModules = lib.mkIf (systemSettings.bootSSH == true) [ "r8169" ];
      systemd.users.root.shell = lib.mkIf (systemSettings.bootSSH == true) "/bin/cryptsetup-askpass";
      network = lib.mkIf (systemSettings.bootSSH == true) {
        enable = true;
        ssh = {
          enable = true;
          port = 22;
          authorizedKeys = systemSettings.authorizedKeys; # SSH keys
          hostKeys = systemSettings.hostKeys;
        };
      }; 
      luks.devices = lib.mkIf (systemSettings.openLUKS == true) {
        "${systemSettings.disk1_name}" = {
          device = systemSettings.disk1_path;
        };
        "${systemSettings.disk2_name}" = {
          device = systemSettings.disk2_path;
        };
        "${systemSettings.disk3_name}" = {
          device = systemSettings.disk3_path;
        };
      };
    };

    # # Open DATA_4TB LUKS on Boot
    # initrd.luks.devices."DATA_4TB" = {
    #   device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
    # };

    # # Open TimeShift LUKS on Boot
    # initrd.luks.devices."TimeShift" = {
    #   device = "/dev/disk/by-uuid/04aaf88f-c0dd-40ad-be7e-85e29c0bd719";
    # };

    # # Open Machines LUKS on Boot
    # initrd.luks.devices."Machines" = {
    #   device = "/dev/disk/by-uuid/452c53a6-0578-4c38-840d-87f1f3f34ddb";
    # };
  };


    
}
