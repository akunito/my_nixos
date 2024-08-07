{ config, pkgs, ... }:

{ 
  # SSH on Boot > https://nixos.wiki/wiki/Remote_disk_unlocking
  boot.kernelParams = [ "ip=dhcp" ];
  boot.initrd = {
    availableKernelModules = [ "r8169" ];
    systemd.users.root.shell = "/bin/cryptsetup-askpass";
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 22;
        authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" ]; # update with your client key
        # hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];
        hostKeys = [ "/home/akunito/.ssh/ssh_host_rsa_key" ];
      };
    };
  };

  # To add LUKS devices
    # 1. Add the UUID to the boot.initrd.luks.devices as below.
    # 2. Install.sh and Reboot the system. The device should be now unlocked on /dev/mapper
    # 3. Run a command to mount the device: $ sudo mount /dev/mapper/DATA_4TB /mnt/DATA_4TB
    # 4. The device should be now mounted. 
    #    When you install.sh again, the device is added automatically to hardware-configuration.nix
    #    If you try to add it manually on configuration.nix or here, there will be conflicts probably.
    
  # Open DATA_4TB LUKS on Boot
  boot.initrd.luks.devices."DATA_4TB" = {
      device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
    };

  # Open TimeShift LUKS on Boot
  boot.initrd.luks.devices."TimeShift" = {
      device = "/dev/disk/by-uuid/04aaf88f-c0dd-40ad-be7e-85e29c0bd719";
    };
}
