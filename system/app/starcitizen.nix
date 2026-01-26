{ pkgs, pkgs-unstable, systemSettings, lib, inputs, ... }:

{
  environment.systemPackages = lib.mkIf (systemSettings.starcitizenEnable == true) [ 
    inputs.nix-citizen.packages.${systemSettings.system}.rsi-launcher
  ];

  boot.kernel.sysctl = lib.mkIf (systemSettings.starcitizenEnable == true) {
    "vm.max_map_count" = 16777216;
    "fs.file-max" = 524288;
  };
}
