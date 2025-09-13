{ config, pkgs, ... }:

{
  boot.kernel.sysctl = {
    "vm.max_map_count" = 16777216;
    "fs.file-max" = 524288;
  };

  # To install the launcher, use flatpak instructions:
  # https://wiki.starcitizen-lug.org/Alternative-Installations#flatpak-installation
}
