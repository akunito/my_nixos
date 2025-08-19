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

      # luks.devices = lib.mkIf (systemSettings.openLUKSdisks == true) {
      #   "${systemSettings.disk1_name}" = lib.mkIf (systemSettings.disk1_enabled == true) {
      #     device = systemSettings.disk1_path;
      #     fsType = systemSettings.disk1_fsType;
      #     options = systemSettings.disk1_options;
      #   };
      #   "${systemSettings.disk2_name}" = lib.mkIf (systemSettings.disk2_enabled == true) {
      #     device = systemSettings.disk2_path;
      #     fsType = systemSettings.disk2_fsType;
      #     options = systemSettings.disk2_options;
      #   };
      #   "${systemSettings.disk3_name}" = lib.mkIf (systemSettings.disk3_enabled == true) {
      #     device = systemSettings.disk3_path;
      #     fsType = systemSettings.disk3_fsType;
      #     options = systemSettings.disk3_options;
      #   };
      #   "${systemSettings.disk4_name}" = lib.mkIf (systemSettings.disk4_enabled == true) {
      #     device = systemSettings.disk4_path;
      #     fsType = systemSettings.disk4_fsType;
      #     options = systemSettings.disk4_options;
      #   };
      # };

      # luks.devices."luks-a40d2e06-e814-4344-99c8-c2e00546beb3".device = "/dev/disk/by-uuid/a40d2e06-e814-4344-99c8-c2e00546beb3";

      # luks.devices."2nd_NVME".device = "/dev/disk/by-uuid/a949132d-9469-4d17-af95-56fdb79f9e4b";

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
