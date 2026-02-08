# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ ... }:
{
  imports =
    [ ../work/configuration.nix # Personal is essentially work system + games.
      ../../system/hardware-configuration.nix
      ../../system/packages/system-basic-tools.nix # Basic system packages (vim, rsync, cryptsetup, etc.)
      ../../system/packages/system-network-tools.nix # Advanced networking tools (nmap, traceroute, etc.)
      ../../system/app/gamemode.nix # GameMode for performance tuning (This is breaking my system, probably AMDGPU driver related)
      ../../system/app/steam.nix
      ../../system/app/proton.nix
      ../../system/app/starcitizen.nix # Kernel tweaks only (packages in games.nix)
      # ../../system/app/prismlauncher.nix # Minecraft Launcher
      ../../system/hardware/nfs_client.nix # NFS share directories over network
      ../../system/hardware/keychron.nix # Keychron keyboard udev rules for WebHID access
      ../../system/security/sudo.nix
      ../../system/security/gpg.nix
      ../../system/security/blocklist.nix
      ../../system/security/firewall.nix
      ../../system/app/control-panel.nix # NixOS infrastructure control panel (web)
      ../../system/app/control-panel-native.nix # NixOS infrastructure control panel (native desktop app)
    ];


}

