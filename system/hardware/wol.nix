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
#   wolDisableEee = true;             # stop the NIC flapping (see below)
#   wolAdvertise = "0x020";           # pin 1000baseT/Full
#
# A flapping WoL NIC is not a cosmetic problem: NetworkManager reconfigures on
# every carrier change and tailscaled answers with "LinkChange: major, rebinding",
# which closes the DERP connection and kills long-lived TCP sessions riding the
# tunnel — even sessions that never touched this NIC. Hence the link tuning.
#
# Verify after applying:
#   sudo ethtool eno1 | grep Wake-on          # expect "Wake-on: g"
#   sudo ethtool --show-eee eno1              # expect "EEE status: disabled"
#   sudo ethtool eno1 | grep -A3 "Advertised link modes"
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
  disableEee = cfg.wolDisableEee or false;
  advertise = cfg.wolAdvertise or "";

  # Everything that has to be (re)applied to the NIC whenever it comes up: link
  # tuning first, WoL arming last so a renegotiation triggered by `advertise`
  # cannot leave the NIC unarmed. Each step is best-effort — a driver that does
  # not implement one must not fail the unit and skip the arming below it.
  armScript = pkgs.writeShellScript "wol-arm-${iface}" (''
  '' + lib.optionalString (advertise != "") ''
    ${pkgs.ethtool}/bin/ethtool -s ${iface} advertise ${advertise} || true
  '' + lib.optionalString disableEee ''
    ${pkgs.ethtool}/bin/ethtool --set-eee ${iface} eee off || true
  '' + ''
    ${pkgs.ethtool}/bin/ethtool -s ${iface} wol g || true
  '');

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
      description = "Arm Wake-on-LAN (magic packet) + link tuning on ${iface}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${armScript}";
      };
    };

    # (c) Re-arm after resume (S3) as a final safety net. Implemented as a
    #     dedicated systemd unit (NOT powerManagement.resumeCommands, which
    #     only materializes when powerManagement.enable = true — false on the
    #     laptop profiles, so the re-arm would silently no-op there).
    systemd.services.wol-rearm-resume = {
      description = "Re-arm Wake-on-LAN (magic packet) + link tuning on ${iface} after resume";
      after = [
        "systemd-suspend.service"
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${armScript}";
      };
    };

    # (d) When the WoL NIC has an IP on the same subnet as another interface
    #     (e.g. bond0), prevent ARP flux (switch MAC-table flapping -> network
    #     hangs): each interface answers ARP only for its own IPs, using its own
    #     source address. This lets eno1 keep an IP (needed for WoL to survive
    #     S3 — method=disabled drops the NIC's WoL-armed state) without flux.
    boot.kernel.sysctl = lib.mkIf (staticIp != "") {
      "net.ipv4.conf.all.arp_ignore" = lib.mkDefault 1;
      "net.ipv4.conf.all.arp_announce" = lib.mkDefault 2;
      "net.ipv4.conf.${iface}.arp_ignore" = 1;
      "net.ipv4.conf.${iface}.arp_announce" = 2;
    };
  };
}
