{ userSettings, systemSettings, pkgs, lib, ... }:

{
  security.sudo = {
    enable = systemSettings.sudoEnable;
    extraRules = lib.mkIf (systemSettings.sudoNOPASSWD == true) [{
      users = [ "${userSettings.username}" ];
      # groups = [ "wheel" ];
      commands = systemSettings.sudoCommands;
    }];
    extraConfig = with pkgs; ''
      Defaults:picloud secure_path="${lib.makeBinPath [
        systemd
      ]}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
    '' + lib.optionalString (systemSettings.sudoTimestampTimeoutMinutes != null) ''
      Defaults:${userSettings.username} timestamp_timeout=${toString systemSettings.sudoTimestampTimeoutMinutes}
    '';
  };

  # security.doas.enable = systemSettings.doasEnable;
  # security.doas.extraRules = [{
  #   users = [ "${userSettings.username}" ];
  #   noPass = systemSettings.DOASnoPass;
  #   keepEnv = true;
  #   persist = true;
  # }];

  # environment.systemPackages = lib.mkIf (systemSettings.wrappSudoToDoas == true) [
  #   # Alias sudo to doas
  #   (pkgs.writeScriptBin "sudo" ''exec doas "$@"'')
  # ];
}
