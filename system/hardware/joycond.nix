{ config, pkgs, lib, systemSettings, ... }:

{
  # Enable joycond daemon: combines Joy-Con pairs into a single virtual gamepad
  # via uinput, so games (including Wine/Bottles) see a standard controller.
  services.joycond.enable = true;

  # Ensure the kernel HID driver for Joy-Cons is loaded
  boot.kernelModules = [ "hid_nintendo" ];
}
