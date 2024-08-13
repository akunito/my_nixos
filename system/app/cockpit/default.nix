{ pkgs, ... }:

{
  virtual-machines = pkgs.callPackage ./virtual-machines.nix { };
  # podman-containers = pkgs.callPackage ./podman-containers.nix { };
}