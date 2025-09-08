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

  fileSystems = lib.mkMerge [
    (lib.mkIf (systemSettings.disk1_enabled) {
      "${systemSettings.disk1_name}" = {
        device = systemSettings.disk1_device;
        fsType = systemSettings.disk1_fsType;
        options = systemSettings.disk1_options;
      };
    })
    (lib.mkIf (systemSettings.disk2_enabled) {
      "${systemSettings.disk2_name}" = {
        device = systemSettings.disk2_device;
        fsType = systemSettings.disk2_fsType;
        options = systemSettings.disk2_options;
      };
    })
    (lib.mkIf (systemSettings.disk3_enabled) {
      "${systemSettings.disk3_name}" = {
        device = systemSettings.disk3_device;
        fsType = systemSettings.disk3_fsType;
        options = systemSettings.disk3_options;
      };
    })
    (lib.mkIf (systemSettings.disk4_enabled) {
      "${systemSettings.disk4_name}" = {
        device = systemSettings.disk4_device;
        fsType = systemSettings.disk4_fsType;
        options = systemSettings.disk4_options;
      };
    })
    (lib.mkIf (systemSettings.disk5_enabled) {
      "${systemSettings.disk5_name}" = {
        device = systemSettings.disk5_device;
        fsType = systemSettings.disk5_fsType;
        options = systemSettings.disk5_options;
      };
    })
    (lib.mkIf (systemSettings.disk6_enabled) {
      "${systemSettings.disk6_name}" = {
        device = systemSettings.disk6_device;
        fsType = systemSettings.disk6_fsType;
        options = systemSettings.disk6_options;
      };
    })
  ];
}
