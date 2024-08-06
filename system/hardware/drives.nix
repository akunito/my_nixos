{ config, pkgs, ... }:

{ 

  # # Reconnect network
  # systemd.services.reconnect-network = {
  #   description = "Reconnect network interface";
  #   after = [ "network.target" "NetworkManager.service" ];
  #   wantedBy = [ "multi-user.target" ];

  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = ''
  #       ${pkgs.iproute}/bin/ip link set eno1 down && sleep 5 && ${pkgs.iproute}/bin/ip link set eno1 up
  #     '';
  #     RemainAfterExit = true;
  #   };
  # };

  # Static IP
  networking.interfaces.eth0.ipv4.addresses = [ { # check that eth0 is the right interface to use
    address = "192.168.0.80";
    prefixLength = 24;
  } ];
  networking.hostName = "nixosaku";
  networking.defaultGateway = "192.168.0.1";
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];

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

  # Open DATA_4TB LUKS on Boot
  boot.initrd.luks.devices."DATA_4TB" = {
      device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
    };

  # Open TimeShift LUKS on Boot
  boot.initrd.luks.devices."TimeShift" = {
      device = "/dev/disk/by-uuid/04aaf88f-c0dd-40ad-be7e-85e29c0bd719";
    };
}
