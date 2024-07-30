# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ ... }:
{
  imports =
    [ ../work/configuration.nix # Personal is essentially work system + games
      ../../system/hardware-configuration.nix
      # ../../system/app/gamemode.nix
      # ../../system/app/steam.nix
      # ../../system/app/prismlauncher.nix
      ../../system/security/doas.nix
      ../../system/security/gpg.nix
      ../../system/security/blocklist.nix
      ../../system/security/firewall.nix
      ( import ../../system/security/sshd.nix {
        authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM/TKh6hv6ZJl7k2rlmDPUgg1iTcFA82HSLYgV+L4m6Z diego88aku@gmail.com"]; 
        inherit userSettings; })
    ];
}
