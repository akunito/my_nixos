{ pkgs, config, lib, ... }:

{
  home.packages = with pkgs; [
    blueman
  ];
  services = {
    blueman-applet.enable = true;
  };
}
