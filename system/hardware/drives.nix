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
    };
  };

  fileSystems."${systemSettings.disk1_name}" = lib.mkIf (systemSettings.disk1_enabled == true) {
    device = systemSettings.disk1_device;
    fsType = systemSettings.disk1_fsType;
    options = systemSettings.disk1_options;
  };
  fileSystems."${systemSettings.disk2_name}" = lib.mkIf (systemSettings.disk2_enabled == true) {
    device = systemSettings.disk2_device;
    fsType = systemSettings.disk2_fsType;
    options = systemSettings.disk2_options;
  };
  fileSystems."${systemSettings.disk3_name}" = lib.mkIf (systemSettings.disk3_enabled == true) {
    device = systemSettings.disk3_device;
    fsType = systemSettings.disk3_fsType;
    options = systemSettings.disk3_options;
  };
  fileSystems."${systemSettings.disk4_name}" = lib.mkIf (systemSettings.disk4_enabled == true) {
    device = systemSettings.disk4_device;
    fsType = systemSettings.disk4_fsType;
    options = systemSettings.disk4_options;
  };
  fileSystems."${systemSettings.disk5_name}" = lib.mkIf (systemSettings.disk5_enabled == true) {
    device = systemSettings.disk5_device;
    fsType = systemSettings.disk5_fsType;
    options = systemSettings.disk5_options;
  };

}
