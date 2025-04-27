{ config, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest; # linuxPackages_latest
  boot.consoleLogLevel = 0;
}
