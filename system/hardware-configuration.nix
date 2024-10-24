# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "uas" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" =
    { device = "/dev/disk/by-uuid/612f9fc9-3fc0-4c87-bd8a-35842e9dcb1f";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-b1b0b2cf-1cc4-467a-943c-0057e748b6a3".device = "/dev/disk/by-uuid/b1b0b2cf-1cc4-467a-943c-0057e748b6a3";

  fileSystems."/home" =
    { device = "/dev/disk/by-uuid/031e9342-2041-4777-a28b-d562fd3ad1f2";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-4e2319df-5473-4eb5-9f00-483253a7f96e".device = "/dev/disk/by-uuid/4e2319df-5473-4eb5-9f00-483253a7f96e";

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/C582-8ED6";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  swapDevices = [ ];

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.br-476415fef1ac.useDHCP = lib.mkDefault true;
  # networking.interfaces.docker0.useDHCP = lib.mkDefault true;
  # networking.interfaces.eno1.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp9s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
