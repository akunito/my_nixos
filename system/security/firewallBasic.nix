{ ... }:

{
  # Firewall
  networking.firewall.enable = true;
  # Open ports in the firewall.
  # syncthing ports (22000/21027) removed 2026-10-01: syncthing retired.
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}