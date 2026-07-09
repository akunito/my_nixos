# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  lib,
  systemSettings,
  ...
}:
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
    ]
    ++ lib.optional (systemSettings.webcamControlsEnable or false) ../../system/hardware/webcam-controls.nix # Persist v4l2 webcam controls across reboot/hotplug
    ++ lib.optional (systemSettings.networkBondingEnable or false) ../../system/hardware/network-bonding.nix # Network bonding (LACP)
    ++ lib.optional (systemSettings.prometheusWorkstationExporterEnable or false) ../../system/app/prometheus-workstation-exporter.nix # Lightweight metrics exporter for workstations
    ++ lib.optional (systemSettings.wifiAuditEnable or false) ../../system/security/wifi-audit.nix # WiFi security audit toolkit (aircrack-ng + hashcat + wireshark)
    ++ lib.optional (systemSettings.wolEnable or false) ../../system/hardware/wol.nix # Persist Wake-on-LAN arming on a dedicated NIC (woken by pfSense)
    ++ lib.optional (systemSettings.llamaServerEnable or false) ../../system/app/llama-server.nix; # Local LLM inference server (llama.cpp Vulkan, OpenAI-compatible)
}

