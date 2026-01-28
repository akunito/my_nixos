{
  config,
  lib,
  pkgs,
  systemSettings,
  ...
}:
{
  config = lib.mkIf (systemSettings.systemNetworkToolsEnable or false) {
    environment.systemPackages = with pkgs; [
      # === Networking Tools (Advanced) ===
      nmap
      wpa_supplicant
      traceroute
      iproute2
      dnsutils
      nettools
    ];
  };
}
