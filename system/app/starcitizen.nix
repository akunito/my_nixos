{ config, pkgs, ... }:

{
  # the installer is included on user/app/games/starcitizen.nix

  boot.kernel.sysctl = {
    "vm.max_map_count" = 16777216;
    "fs.file-max" = 524288;
  };
}
