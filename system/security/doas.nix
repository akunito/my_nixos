{ userSettings, pkgs, ... }:

{
  # Doas instead of sudo
  security.doas.enable = true;
  security.sudo.enable = false;
  security.doas.extraRules = [{
    users = [ "${userSettings.username}" "wheel" ];
    keepEnv = true;
    persist = true;
  }];

  environment.systemPackages = [
    # Alias sudo to doas
    (pkgs.writeScriptBin "sudo" ''exec doas "$@"'')
  ];
}
