{ pkgs, userSettings, systemSettings, ... }: 

{
  ## Update flake inputs daily
  systemd.services = {
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
}