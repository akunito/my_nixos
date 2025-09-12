{ config, pkgs, lib, systemSettings, ... }:

{
    # NOTE you might need to add xpad as Kernel Module on your flake.nix

    hardware.xone.enable = false; # Xbox wireless controller # DISABLE because 24.11 kernel does not support it
    hardware.xpadneo.enable = true; # Enable the xpadneo driver for Xbox One controllers

    environment.systemPackages = with pkgs; [
        gamepad-tool
    ];

    boot.extraModprobeConfig = ''
      options bluetooth disable_ertm=Y
    '';
}