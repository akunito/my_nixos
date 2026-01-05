{ config, pkgs, lib, userSettings, systemSettings, ... }:

{
  imports = [
    ./default.nix
    ./waybar.nix
    ./dock.nix
    ./rofi.nix
  ];
}

