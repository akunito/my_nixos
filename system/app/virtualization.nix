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
    # # extraConfig > Extra contents appended to the libvirtd configuration file, libvirtd.conf.
    # extraConfig = ''
    #   unix_sock_group = 'libvirt'
    #   unix_sock_rw_perms = '0770'
    # '';
  };
  
  # TESTING ================================================
  # Create libvirt user
  users.groups.libvirt = { # add also your user to libvirt group 
    name = "libvirt";
  };

  # # /etc/libvirt/libvirtd.conf
  # environment.etc."/libvirt/libvirtd.conf".text = ''
  # unix_sock_group = "libvirt"
  # unix_sock_rw_perms = "0770"
  #   '';

  # # /etc/libvirt/qemu.conf
  # environment.etc."/libvirt/qemu.conf".text = ''
  # # Some examples of valid values are:
  # #
  # #       user = "qemu"   # A user named "qemu"
  # #       user = "+0"     # Super user (uid=0)
  # #       user = "100"    # A user named "100" or a user with uid=100
  # #
  # user = "akunito"

  # # The group for QEMU processes run by the system instance. It can be
  # # specified in a similar way to user.
  # group = "akunito"
  #   '';

  # # redirect ports for printer to be tested
  # virtualisation.spiceUSBRedirection.enable = true; 
}
