# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ ... }:
{
  imports =
    [ ../work/configuration.nix # Personal is essentially work system + games.
      ../../system/hardware-configuration.nix
      # ../../system/app/gamemode.nix # GameMode for performance tuning (This is breaking my system, probably AMDGPU driver related)
      ../../system/app/steam.nix
      # ../../system/app/prismlauncher.nix # Minecraft Launcher
      ../../system/hardware/nfs_client.nix # NFS share directories over network
      ../../system/security/sudo.nix
      ../../system/security/gpg.nix
      ../../system/security/blocklist.nix
      ../../system/security/firewall.nix
      ../../system/hardware/drives.nix # SSH on Boot to unlock LUKS drives + Open my LUKS drives (OPTIONAL)
    ];


}

