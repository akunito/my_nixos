{ systemSettings, userSettings, ... }:

{
  imports = [ ./base.nix
              ( import ../../system/security/sshd.nix {
                authorizedKeys = systemSettings.authorizedKeys; # SSH keys
                inherit userSettings; })
            ];
}
