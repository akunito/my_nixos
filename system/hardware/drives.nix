{ ... }:

{
  # # Open DATA_4TB LUKS on Boot (it needs pass or keyfile on an uncrypted drive)
  # boot.initrd.luks.devices.DATA_4TB = {
  #   device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
  #   keyFile = "/root/luks-keyfile-DATA_4TB";
  #   preLVM = true;
  # };

  # # Open Linux_Data LUKS after Boot
  # environment.etc.crypttab.text = ''
  #   Linux_Data UUID=f5ea12fe-ffc8-453f-a3d1-537bc1a0275b /root/luks-keyfile-Linux_Data
  #   '';
  # # Mount Linux_Data
  # fileSystems."/mnt/Linux_Data" = {
  #   device = "/dev/disk/by-uuid/92c3258e-fa91-4588-b430-8a58b0474a8a";
  # };

  # fileSystems."/boot" =
  #   { device = "/dev/disk/by-uuid/C643-9D25";
  #     fsType = "vfat";
  #     options = [ "fmask=0022" "dmask=0022" ];
  #   };

  # fileSystems."/" =
  #   { device = "/dev/disk/by-uuid/cbecfc7d-797b-46c7-8aa8-5be912d95661";
  #     fsType = "ext4";
  #   };

  # SSH on Boot > https://nixos.wiki/wiki/Remote_disk_unlocking
  boot.kernelParams = [ "ip=192.168.0.80::192.168.0.1:255.255.255.0:myhost::none" ]; # where 192.168.0.80 is the IP of myhost
  boot.initrd = {
    availableKernelModules = [ "r8169" ];
    systemd.users.root.shell = "/bin/cryptsetup-askpass";
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 22;
        authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" ]; # update with your client key
        hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ]; # to be generated after intalling nixos
      };
    };
  };


  # # Open DATA_4TB LUKS after Boot.
  # environment.etc.crypttab.text = ''
  #   DATA_4TB UUID=231c229c-1daf-43b5-85d0-f1691fa3ab93 /root/luks-keyfile-DATA_4TB luks
  #   '';

  # boot.initrd.luks.devices."DATA_4TB" = {
  #     device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
  #     preLVM = false;
  #     keyFile = "/root/luks-keyfile-DATA_4TB";
  #   };
  fileSystems."/mnt/DATA_4TB" =
    { device = "/dev/disk/by-uuid/0c739f88-5add-4d7c-8c61-b80171341daf";
      fsType = "ext4";
    };

  # systemd.services.unlock-data4tb = {
  #   description = "Unlock LUKS device for DATA_4TB";
  #   wants = [ "local-fs.target" ];
  #   after = [ "local-fs.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = ''
  #       /run/current-system/sw/bin/mount -t ext4 /dev/mapper/DATA_4TB /mnt/DATA_4TB
  #     '';
  #     RemainAfterExit = true;
  #     # Retry logic
  #     Restart = "on-failure";        # Restart the service on failure
  #     RestartSec = 30;               # Wait 30 seconds before retrying
  #     StartLimitIntervalSec = 0;     # Disable rate limiting for restarts
  #     StartLimitBurst = 5;           # Allow up to 5 restarts within 0 seconds
  #     };
  #   wantedBy = [ "multi-user.target" ];
  # };

  # # Mount DATA_4TB
  # fileSystems."/mnt/DATA_4TB" = {
  #   # depends = [
  #   #     # The mounts above have to be mounted in this given order
  #   #     "/"
  #   # ];
  #   device = "/dev/disk/by-uuid/0c739f88-5add-4d7c-8c61-b80171341daf";
  #   fsType = "ext4";
  #   options = [ "bind" ];   # Any mount options (optional)
  #   # neededForBoot = false;      # Set this to true if the disk is required for booting.
  # };

  # if permissions issues check https://github.com/NixOS/nixpkgs/issues/55807

}
