{ config, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_latest; # linuxPackages_xanmod_latest;
  boot.consoleLogLevel = 0;
}
