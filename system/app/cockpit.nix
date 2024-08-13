{ config, pkgs, lib, ... }:

# DRAFT TO BE REMOVED

let
  cockpit-apps = pkgs.callPackage ./cockpit/default.nix { };
in
{
  imports =
  [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  environment.systemPackages = with pkgs; [
     cockpit
     # cockpit-apps.podman-containers
     cockpit-apps.virtual-machines
     libvirt # needed for virtual-machines
     virt-manager # needed for virtual-machines
  ];

# Add the rest of the configuration here

}