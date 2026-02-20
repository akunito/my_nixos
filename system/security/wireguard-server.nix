# WireGuard Server — Point-to-Point Backup Tunnel (VPS <-> pfSense)
#
# Provides a backup VPN tunnel between VPS and home LAN via pfSense.
# This is a fallback path if Tailscale/Headscale goes down.
#
# Configuration:
#   systemSettings.wireguardServerEnable = true;
#   systemSettings.wireguardServerPort = 51820;
#   systemSettings.wireguardServerIp = "172.26.5.155/24";
#   systemSettings.wireguardServerPrivateKeyFile = "/etc/secrets/wireguard/private.key";
#   systemSettings.wireguardServerPeers = [{
#     publicKey = "...";           # pfSense WG public key (from secrets)
#     allowedIPs = [ "192.168.8.0/24" "172.26.5.1/32" ];
#     persistentKeepalive = 25;
#   }];
#
# Setup:
#   1. Copy private key from old VPS: grep PrivateKey wg0.conf | awk '{print $3}'
#   2. Save to /etc/secrets/wireguard/private.key (chmod 600)
#   3. Update pfSense WireGuard peer endpoint to new VPS IP
#   4. Verify: wg show

{ config, lib, pkgs, systemSettings, ... }:

let
  port = systemSettings.wireguardServerPort or 51820;
  tunnelIp = systemSettings.wireguardServerIp or "172.26.5.155/24";
  privateKeyFile = systemSettings.wireguardServerPrivateKeyFile or "/etc/secrets/wireguard/private.key";
  peers = systemSettings.wireguardServerPeers or [];
in
lib.mkIf (systemSettings.wireguardServerEnable or false) {
  networking.wireguard.interfaces.wg0 = {
    listenPort = port;
    privateKeyFile = privateKeyFile;
    ips = [ tunnelIp ];

    # MTU tuning — multiple encapsulation layers reduce effective MTU (NET-AUDIT-05)
    mtu = 1420;

    peers = map (peer: {
      publicKey = peer.publicKey;
      allowedIPs = peer.allowedIPs or [ "192.168.8.0/24" ];
      persistentKeepalive = peer.persistentKeepalive or 25;
    }) peers;
  };

  # Firewall — allow WireGuard port
  networking.firewall.allowedUDPPorts = [ port ];

  # IP forwarding for routing through the tunnel
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  environment.systemPackages = [ pkgs.wireguard-tools ];
}
