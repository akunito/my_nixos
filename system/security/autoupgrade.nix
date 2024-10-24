{ pkgs, userSettings, systemSettings, lib, inputs, ... }: 

{
  system.autoUpgrade = lib.mkIf (systemSettings.autoUpdate == true) {
    enable = true;
    flake = "${userSettings.dotfilesDir}#system"; # where <#system> depends of your flake (nix flake show flake.nix)
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
    dates = systemSettings.autoUpdate_dates;
    randomizedDelaySec = systemSettings.autoUpdate_randomizedDelaySec;
  };
}

