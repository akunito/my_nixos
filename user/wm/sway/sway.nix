{ config, pkgs, lib, userSettings, systemSettings, ... }:

{
  imports = [
    ./default.nix
    ./waybar.nix
    ./rofi.nix
  ];
}

