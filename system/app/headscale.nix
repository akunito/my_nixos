# Headscale — Self-hosted Tailscale Coordination Server
#
# Provides mesh VPN coordination for all Tailscale clients (phones, laptops, servers).
# Runs as a NixOS-native service (not Docker) on the VPS.
#
# Configuration:
#   systemSettings.headscaleEnable = true;
#   systemSettings.headscaleDomain = secrets.headscaleDomain;  # e.g., "headscale.example.com"
#   systemSettings.headscalePort = 443;
#
# After deployment:
#   1. Import migrated database: cp /tmp/headscale-state-backup.sqlite3 /var/lib/headscale/db.sqlite3
#   2. Verify: headscale users list
#   3. Verify: headscale nodes list
#
# Database: SQLite at /var/lib/headscale/db.sqlite3 (migrated from old VPS Docker Headscale)

{ config, lib, pkgs, systemSettings, ... }:

let
  domain = systemSettings.headscaleDomain or "";
  port = systemSettings.headscalePort or 443;
in
lib.mkIf (systemSettings.headscaleEnable or false) {
  services.headscale = {
    enable = true;
    port = port;

    settings = {
      server_url = "https://${domain}";

      # Database — SQLite (simple, sufficient for <100 nodes)
      database = {
        type = "sqlite3";
        sqlite.path = "/var/lib/headscale/db.sqlite3";
      };

      # IP allocation for Tailscale clients
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };

      # DNS configuration pushed to clients
      dns = {
        nameservers.global = [ "1.1.1.1" "9.9.9.9" ];
        magic_dns = true;
        base_domain = "tailnet.${domain}";
      };

      # DERP (relay) — use Tailscale's public DERP servers
      derp = {
        server = {
          enabled = false; # Use external DERP; enable later if self-hosting
        };
        urls = [ "https://controlplane.tailscale.com/derpmap/default" ];
        auto_update_enabled = true;
        update_frequency = "24h";
      };

      # Logging
      log = {
        format = "text";
        level = "info";
      };

      # Policy — ACL file (optional, deploy later)
      # policy.path = "/etc/headscale/acl.hujson";
    };
  };

  # Firewall — allow Headscale port
  networking.firewall.allowedTCPPorts = [ port ];

  # Headplane (web UI) — DISABLED for now (not tested, security not reviewed)
  # Use CLI only: headscale users list, headscale nodes list, headscale routes list
  # Re-evaluate Headplane after VPN migration is stable and security-audited

  environment.systemPackages = [ pkgs.headscale ];
}
