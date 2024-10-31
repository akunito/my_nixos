{ userSettings, systemSettings, pkgs, lib, ... }:

{
  # Doas instead of sudo
  security.doas.enable = systemSettings.doasEnable;
  security.sudo.enable = systemSettings.sudoEnable;

  security.sudo.extraRules = lib.mkIf (systemSettings.sudoNOPASSWD == true) [{
    users = [ "${userSettings.username}" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" "SETENV" ];
    }];
  }];

  security.doas.extraRules = [{
    users = [ "${userSettings.username}" ];
    noPass = systemSettings.DOASnoPass;
    keepEnv = true;
    persist = true;
  }];

  environment.systemPackages = lib.mkIf (systemSettings.wrappSudoToDoas == true) [
    # Alias sudo to doas
    (pkgs.writeScriptBin "sudo" ''exec doas "$@"'')
  ];
}
