# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ ... }:
{
  imports =
    [ ../work/configuration.nix # Personal is essentially work system + games
      ../../system/hardware-configuration.nix
      # ../../system/app/gamemode.nix
      # ../../system/app/steam.nix
      # ../../system/app/prismlauncher.nix
      ../../system/security/doas.nix
      ../../system/security/gpg.nix
      ../../system/security/blocklist.nix
      ../../system/security/firewall.nix
    ];

  # Open LUKS devices
  # boot.initrd.luks.devices = {
  #   data = {
  #     device = "/dev/sdb1";  # Encrypted partition
  #     preLVM = true;          # If you use LVM on top of LUKS, otherwise omit this line
  #   };
  # };

  # Mount DATA_4TB disk on /mnt/data
  fileSystems = {
    "/mnt/DATA_4TB" = {  # Replace with your desired mount point
      device = "/dev/sdb1";  # by device
      # device = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";  # by UUID (get them with 'sudo blkid')
      fsType = "ext4";  # Replace with the correct file system type
      options = [ "defaults" "noatime" ];  # Additional mount options, adjust as necessary
    };
  };

}

