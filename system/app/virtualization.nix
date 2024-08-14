{ config, pkgs, lib, ... }:

{
  # Virt-manager doc > https://nixos.wiki/wiki/Virt-manager
  # Note there is another virtualization.nix on user folder
<<<<<<< HEAD
  environment.systemPackages = with pkgs; [ virt-manager distrobox ];
=======
  environment.systemPackages = with pkgs; [
    virt-manager
    distrobox
  ];

>>>>>>> ec7ad38 (removing cockpit as virtual-machines not supported yet)
  programs.virt-manager.enable = true;
  virtualisation.libvirtd = {
    # To enable networks check the doc above
    allowedBridges = [
      "nm-bridge"
      "virbr0"
    ];
    enable = true;
    qemu.runAsRoot = false;
  };

  # # redirect ports for printer to be tested
  # virtualisation.spiceUSBRedirection.enable = true; 
}
