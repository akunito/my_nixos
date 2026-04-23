# WiFi Security Audit Toolkit
#
# Enable via: systemSettings.wifiAuditEnable = true
#
# AUTHORIZED testing only — for networks you own or have written permission
# to test. Hardware notes for built-in MT7921 (mt76 driver):
#   - Monitor mode + PMKID capture via hcxdumptool: works well.
#   - Active deauth/injection: works but mediocre success rate.
#   - WPS PIN attacks: unreliable on this chip — not included.
#
# GPU acceleration: AMD ROCm OpenCL ICD is wired by system/hardware/opengl.nix
# when systemSettings.gpuType == "amd". Verify with `hashcat -I` after rebuild.
#
# Wireshark capture without root: programs.wireshark gives dumpcap the needed
# capabilities and creates the `wireshark` group. Add your user with
# `sudo gpasswd -a $USER wireshark`.
#
# hcxdumptool needs CAP_NET_RAW + CAP_NET_ADMIN — wrapped via security.wrappers
# so handshake capture doesn't require sudo.

{ pkgs, systemSettings, userSettings, lib, ... }:

let
  enabled = systemSettings.wifiAuditEnable or false;
in
{
  config = lib.mkIf enabled {
    # Add the profile's user to the `wireshark` group so dumpcap can capture
    # without root. Group itself is created by programs.wireshark below.
    users.users.${userSettings.username}.extraGroups = [ "wireshark" ];

    environment.systemPackages = with pkgs; [
      # Capture & monitor mode
      aircrack-ng
      hcxdumptool
      hcxtools
      mdk4
      macchanger
      iw
      # Cracking
      hashcat
      hashcat-utils
      john
      crunch
      # Inspection (CLI)
      tshark
      tcpdump
      # Orchestration
      wifite2
      # Wordlists (rockyou + many more under share/seclists/)
      seclists
      # OpenCL sanity check
      clinfo
    ];

    # Wireshark GUI + dumpcap capabilities + 'wireshark' group
    programs.wireshark = {
      enable = true;
      package = pkgs.wireshark;
    };

    # Allow hcxdumptool to open raw sockets without sudo
    security.wrappers.hcxdumptool = {
      source = "${pkgs.hcxdumptool}/bin/hcxdumptool";
      capabilities = "cap_net_raw,cap_net_admin+eip";
      owner = "root";
      group = "root";
      permissions = "u+rx,g+rx,o+rx";
    };
  };
}
