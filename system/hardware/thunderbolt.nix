# Thunderbolt support: bolt daemon, auto-authorization, and diagnostic tools
# Enable via thunderboltEnable = true in profile config
{ lib, pkgs, systemSettings, ... }:

lib.mkIf (systemSettings.thunderboltEnable or false) {
  # Enable bolt daemon for Thunderbolt device authorization
  services.hardware.bolt.enable = true;

  # Ensure thunderbolt kernel modules are loaded
  boot.kernelModules = [ "thunderbolt" ];

  # udev rules for Thunderbolt hotplug auto-authorization
  services.udev.extraRules = ''
    # Auto-authorize Thunderbolt devices
    ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", ATTR{authorized}="1"
  '';

  # Diagnostic tools
  environment.systemPackages = with pkgs; [
    usbutils  # lsusb
    bolt      # boltctl for TB management
  ];
}
