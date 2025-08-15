{ config, pkgs, lib, userSettings, ... }:

{
  # Various packages related to virtualization, compatability and sandboxing
  home.packages = with pkgs; lib.mkIf (userSettings.virtualizationEnable == true) [
    # Virtual Machines and wine
    libvirt
    virt-manager
    qemu
    uefi-run
    lxc
    swtpm
    bottles
    virtio-win
  
    # Filesystems
    dosfstools
    virtiofsd
  ];

  home.file.".config/libvirt/qemu.conf".text = ''
  nvram = ["/run/libvirt/nix-ovmf/OVMF_CODE.fd:/run/libvirt/nix-ovmf/OVMF_VARS.fd"]
    '';

  # Virtualization: Connections for virt-manager
  dconf.settings = lib.mkIf (userSettings.virtualizationEnable == true) {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = ["qemu:///system"];
      uris = ["qemu:///system"];
    };
  };

}
