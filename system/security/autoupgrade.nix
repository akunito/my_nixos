{ pkgs, userSettings, systemSettings, lib, ... }: 

{
  # nixos-upgrade.service 
  system.autoUpgrade = lib.mkIf (systemSettings.autoUpdate == true) {
    enable = true;
    flake = "${userSettings.dotfilesDir}#system";
    flags = [
      "--update-input"
      "nixpkgs"
      "--commit-lock-file"
      "-L"
    ];
    dates = systemSettings.autoUpdate_dates;
    persistent = true;
    randomizedDelaySec = systemSettings.autoUpdate_randomizedDelaySec;
  };
}
