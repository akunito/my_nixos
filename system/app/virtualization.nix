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


  virtualisation.vmVariant = {
    # following configuration is added only when building VM with build-vm
    virtualisation = {
      memorySize = 6000; # Use 2048MiB memory.
      cores = 4;
      graphics = true;
    };
  };

  # # QEMU VM settings
  # # Install QEMU Guest Addition
  # services.qemuGuest.enable = userSettings.qemuGuestAddition;
  # # Spice and clipboard
  # systemd.user.services.spice-vdagent-client = lib.mkIf (userSettings.qemuGuestAddition == true) {
  #   description = "spice-vdagent client";
  #   wantedBy = [ "graphical-session.target" ];
  #   serviceConfig = {
  #     ExecStart = "${pkgs.spice-vdagent}/bin/spice-vdagent -x";
  #     Restart = "on-failure";
  #     RestartSec = "5";
  #   };
  # };
  # systemd.user.services.spice-vdagent-client.enable = lib.mkIf (userSettings.qemuGuestAddition == true) lib.mkDefault true;

  virtualisation.waydroid.enable = true;
}
