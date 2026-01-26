{
  pkgs,
  userSettings,
  lib,
  ...
}:

{
  # Steam configuration
  # Controlled by user variable 'steamPackEnable'
  # Maintains system-level integration (firewall, udev, hardware)

  programs.steam = lib.mkIf (userSettings.steamPackEnable == true) {
    enable = true;
    protontricks.enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
  };

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-original"
      "steam-unwrapped"
      "steam-run"
    ];

}
