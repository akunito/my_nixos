{ config, pkgs, systemSettings, ... }:

{
  boot.kernelPackages = systemSettings.kernelPackages;
  boot.consoleLogLevel = 0;
}
