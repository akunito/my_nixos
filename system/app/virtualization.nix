{ config, pkgs, userSettings, lib, ... }:

{
  # Virt-manager doc > https://nixos.wiki/wiki/Virt-manager
  # Note there is another virtualization.nix on user folder
  environment.systemPackages = with pkgs; lib.mkIf (userSettings.virtualizationEnable == true) [
    virt-manager
    distrobox
  ];

  programs.virt-manager.enable = lib.mkIf (userSettings.virtualizationEnable == true) true;
  virtualisation.libvirtd = lib.mkIf (userSettings.virtualizationEnable == true) {
    # To enable networks check the doc above
    allowedBridges = [
      "nm-bridge"
      "virbr0"
    ];
    enable = true;
    qemu.runAsRoot = false;
  };
  
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;  # enable copy and paste between host and guest

  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.virtualizationEnable == true) [ "qemu-libvirtd" "libvirtd" ];

  # # redirect ports for printer to be tested
  # virtualisation.spiceUSBRedirection.enable = true; 
}
