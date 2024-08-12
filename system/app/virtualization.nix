{ config, pkgs, ... }:

{
  # Virt-manager doc > https://nixos.wiki/wiki/Virt-manager
  # Note there is another virtualization.nix on user folder
  environment.systemPackages = with pkgs; [ virt-manager distrobox ];
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
  
  # # TESTING ================================================
  # # Create libvirt user
  # users.groups.libvirt = { # add also your user to libvirt group 
  #   name = "libvirt";
  # };

  # # redirect ports for printer to be tested
  # virtualisation.spiceUSBRedirection.enable = true; 
}
