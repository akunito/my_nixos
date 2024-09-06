{ pkgs, userSettings, systemSettings, lib, ... }: 

{
  ## SystemD service flake-update > to update flake inputs
  systemd.services = lib.mkIf (systemSettings.autoUpdate == true) {
    flake-update = {
      preStart = "${pkgs.host}/bin/host ${systemSettings.hostname}.net";  # Check network connectivity
      unitConfig = {
        Description = "Update flake inputs";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
      serviceConfig = {
        ExecStart = "${pkgs.nix}/bin/nix flake update --commit-lock-file ${userSettings.dotfilesDir}";
        Restart = "on-failure";
        RestartSec = "30";
        Type = "oneshot"; # Ensure that it finishes before starting nixos-upgrade
        User = "${userSettings.username}";
      };
      before = ["nixos-upgrade.service"];
      path = [pkgs.nix pkgs.git pkgs.host];
    };
  };

  system.autoUpgrade = lib.mkIf (systemSettings.autoUpdate == true) {
    enable = true;
    flake = "${userSettings.dotfilesDir}#${systemSettings.hostname}";
    flags = [
      "-L"
    ];
    dates = systemSettings.autoUpdate_dates;
    persistent = true;
    randomizedDelaySec = systemSettings.autoUpdate_randomizedDelaySec;
  };
  # Allow nixos-upgrade to restart on failure (e.g. when laptop wakes up before network connection is set)
  systemd.services.nixos-upgrade = lib.mkIf (systemSettings.autoUpdate == true) {
    preStart = "${pkgs.host}/bin/host ${systemSettings.hostname}.net";  # Check network connectivity
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "120";
    };
    unitConfig = {
      StartLimitIntervalSec = 600;
      StartLimitBurst = 2;
    };
    after = ["flake-update.service"]; # calls SystemD flake-update
    wants = ["flake-update.service"];
    path = [pkgs.host];
  };

}