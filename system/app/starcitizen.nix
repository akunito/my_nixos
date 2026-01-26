{ pkgs, pkgs-unstable, userSettings, lib, inputs, ... }:

{
  # Kernel tweaks for Star Citizen (system-level requirement)
  # Actual launcher is in user/app/games/games.nix
  boot.kernel.sysctl = lib.mkIf (userSettings.starcitizenEnable == true) {
    "vm.max_map_count" = 16777216;
    "fs.file-max" = 524288;
  };
}


