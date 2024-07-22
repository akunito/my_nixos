{ userSettings, ... }:

{
  imports = [ ./base.nix
              ( import ../../system/security/sshd.nix {
                authorizedKeys = [ "ssh-rsa asdfasdf diego88aku@gmail.com"]; # to update with my ssh key
                inherit userSettings; })
            ];
}
