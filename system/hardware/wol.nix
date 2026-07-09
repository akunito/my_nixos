# Wake-on-LAN persistence module
# Arms magic-packet WoL on a dedicated NIC and keeps it armed across reboot,
# NetworkManager reconnects, and resume, so a LAN-side sender (e.g. pfSense)
# can wake this host from S3/S5.
#
# Only certain NICs support WoL. On DESK the onboard 2.5GbE Realtek (eno1)
# supports it (`Supports Wake-on: pumbg`); the 10GbE Intel X520 bond does not.
# So wolInterface must point at the WoL-capable NIC, wired to the LAN.
#
# Usage in profile:
#   wolEnable = true;
#   wolInterface = "eno1";
#   wolStaticIp = "192.168.8.99/24";  # "" = IP-less listener (avoids dual-homing)
#
# Verify after applying:
#   sudo ethtool eno1 | grep Wake-on          # expect "Wake-on: g"
# Wake from another LAN host (pfSense has /usr/local/bin/wol):
#   ssh admin@192.168.8.1 "/usr/local/bin/wol -i 192.168.8.255 <MAC>"
#
# See: memory reference_desk_wol (proven 2026-07-09)
{ config, pkgs, lib, systemSettings, ... }:
let
  cfg = systemSettings;
  enabled = cfg.wolEnable or false;
  iface = cfg.wolInterface or "eno1";
  staticIp = cfg.wolStaticIp or "";
  useNM = cfg.networkManager or false;

  # NetworkManager connection for the WoL NIC. `wake-on-lan=magic` re-arms the
  # NIC every time the connection activates (including after resume) — this is
  # the declarative, driver-agnostic path. IP is either a fixed static address
  # (kept pingable for waker liveness checks) or disabled (pure listener).
  nmWolConnection = ''
    [connection]
    id=wol-${iface}
    type=ethernet
    interface-name=${iface}
    autoconnect=true
    autoconnect-priority=100

    [ethernet]
    wake-on-lan=magic

    [ipv4]
    ${if staticIp != "" then "method=manual\naddress1=${staticIp}" else "method=disabled"}

    [ipv6]
    method=disabled
  '';
in
{
  config = lib.mkIf enabled {
    # (a) Declarative arming via NetworkManager (re-applied on every activation).
    environment.etc = lib.mkIf useNM {
      "NetworkManager/system-connections/wol-${iface}.nmconnection" = {
        text = nmWolConnection;
        mode = "0600";
      };
    };

    system.activationScripts."reloadNMForWol" = lib.mkIf useNM (
      lib.stringAfter [ "etc" ] ''
        if ${pkgs.systemd}/bin/systemctl is-active --quiet NetworkManager; then
          ${pkgs.networkmanager}/bin/nmcli connection reload || true
        fi
      ''
    );

    # (b) Belt-and-suspenders: hard-arm `wol g` via ethtool on boot, in case the
    #     driver ignores NM's wake-on-lan property.
    systemd.services.wol-arm = {
      description = "Arm Wake-on-LAN (magic packet) on ${iface}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${iface} wol g";
      };
    };

    # (c) Re-arm after resume (S3) as a final safety net.
    powerManagement.resumeCommands = ''
      ${pkgs.ethtool}/bin/ethtool -s ${iface} wol g || true
    '';
  };
}
