{ userSettings, ... }:

{
  imports = [ ../homelab/base.nix
              ( import ../../system/security/sshd.nix {
                authorizedKeys = [ "ssh-rsa asdfasdf" ]; # to update with my ssh key
                inherit userSettings; })
            ];
}
