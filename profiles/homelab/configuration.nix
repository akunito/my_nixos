{ userSettings, ... }:

{
  imports = [ ./base.nix
              ( import ../../system/security/sshd.nix {
                authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM/TKh6hv6ZJl7k2rlmDPUgg1iTcFA82HSLYgV+L4m6Z diego88aku@gmail.com"]; # to update with my ssh key
                inherit userSettings; })
            ];
}
