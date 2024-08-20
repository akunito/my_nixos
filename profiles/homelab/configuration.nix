{ userSettings, ... }:

{
  imports = [ ./base.nix
              ( import ../../system/security/sshd.nix {
                authorizedKeys = userSettings.authorizedKeys; # SSH keys
                inherit userSettings;
                inherit lib; })
            ];
}
