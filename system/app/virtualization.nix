{ config, pkgs, userSettings, lib, ... }:

{

  nixpkgs.overlays = [
    (final: prev: {
      libvirt = prev.libvirt.override {
        enableXen = false;
        enableGlusterfs = false;
        enableIscsi = false;
      };
    })
  ];

  # Virt-manager doc > https://nixos.wiki/wiki/Virt-manager
  # Note there is another virtualization.nix on user folder
  environment.systemPackages = with pkgs; lib.mkIf (userSettings.virtualizationEnable == true) [
    virt-manager
    virt-viewer  # Standalone viewer with better SPICE support
    distrobox
    virtiofsd
    # SPICE client packages for clipboard and display integration
    spice
    spice-gtk
    spice-protocol
    # Windows VirtIO tools (provides virtio-win.iso with VirtIO drivers and SPICE guest tools)
    virtio-win
    # gnome-boxes # VM management
    # dnsmasq # VM networking
    phodav # (optional) Share files with guest VMs
    # Note: spice-vdagent is NOT needed on host - it's a guest daemon
  ];

  programs.virt-manager.enable = lib.mkIf (userSettings.virtualizationEnable == true) true;
  
  # Enable dconf for virt-manager UI settings persistence
  # Safe to duplicate - NixOS merges definitions without error
  # (May already be enabled via system/wm/dbus.nix, but this acts as a safeguard)
  programs.dconf.enable = lib.mkIf (userSettings.virtualizationEnable == true) true;
  virtualisation.libvirtd = lib.mkIf (userSettings.virtualizationEnable == true) {
    # To enable networks check the doc above
    allowedBridges = [
      "nm-bridge"
      "virbr0"
    ];
    enable = true;
    onShutdown = "shutdown";
    # Set timeout for guest shutdown (default is 300s/5min, which can cause hangs)
    # After timeout, guests will be force-stopped
    shutdownTimeout = 10;  # 60 seconds - adjust if you have slow-shutting VMs
    qemu = {
      runAsRoot = false;
      package = pkgs.qemu_kvm;
      vhostUserPackages = [ pkgs.virtiofsd ];
      # Enable TPM emulation (for Windows 11)
      swtpm.enable = true;
      # Note: OVMF (UEFI firmware) is now available by default with QEMU
      # The ovmf.enable option has been removed in recent NixOS versions
    };
  };

  # Ensure libvirt-guests service stops before libvirtd and has proper timeout
  # This prevents hanging during system shutdown
  systemd.services.libvirt-guests = lib.mkIf (userSettings.virtualizationEnable == true) {
    # Ensure guests are shut down before libvirtd stops
    before = [ "libvirtd.service" ];
    # Set service timeout to prevent indefinite hanging
    serviceConfig = {
      TimeoutStopSec = 10;  # 10 seconds total timeout (includes shutdownTimeout)
    };
  };

  # Note: These services are for when NixOS runs AS a guest VM, not for managing guest VMs
  # They enable clipboard/resolution syncing when this NixOS system is running inside a VM
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;  # enable copy and paste when NixOS is a guest

  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.virtualizationEnable == true) [ "qemu-libvirtd" "libvirtd" ];
  # Allow VM management
  users.groups.libvirtd.members = [ "akunito" ];
  users.groups.kvm.members = [ "akunito" ];

  # # redirect ports for printer to be tested
  virtualisation.spiceUSBRedirection.enable = true; 

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
