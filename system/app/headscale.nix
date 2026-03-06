# Headscale — Self-hosted Tailscale Coordination Server
#
# Provides mesh VPN coordination for all Tailscale clients (phones, laptops, servers).
# Runs as a NixOS-native service (not Docker) on the VPS.
#
# Configuration:
#   systemSettings.headscaleEnable = true;
#   systemSettings.headscaleDomain = secrets.headscaleDomain;  # e.g., "headscale.example.com"
#   systemSettings.headscalePort = 8080;  # Internal port (nginx handles TLS on 443)
#   systemSettings.acmeEmail = secrets.acmeEmail;  # For Let's Encrypt certificate
#
# After deployment:
#   1. Import migrated database: cp /tmp/headscale-state-backup.sqlite3 /var/lib/headscale/db.sqlite3
#   2. Verify: headscale users list
#   3. Verify: headscale nodes list
#
# TLS: nginx reverse proxy with ACME (Let's Encrypt) when headscaleDomain is set.
# Database: SQLite at /var/lib/headscale/db.sqlite3 (migrated from old VPS Docker Headscale)

{ config, lib, pkgs, pkgs-unstable, systemSettings, ... }:

let
  domain = systemSettings.headscaleDomain or "";
  port = systemSettings.headscalePort or 8080;
  acmeEmail = systemSettings.acmeEmail or "admin@example.com";
  hasDomain = domain != "";

  # Generate extra DNS records from nginxLocalServices so Tailscale clients
  # resolve *.local.akunito.com directly (no split DNS query to pfSense needed).
  # This makes remote access work even when the phone can't reach pfSense.
  nginxLocalServices = systemSettings.nginxLocalServices or {};
  nginxLocalListenAddress = systemSettings.nginxLocalListenAddress or "";
  wildcardLocal = systemSettings.wildcardLocal or "";
  extraDnsRecords = lib.mapAttrsToList (name: _: {
    name = "${name}.${wildcardLocal}";
    type = "A";
    value = nginxLocalListenAddress;
  }) nginxLocalServices;
in
lib.mkIf (systemSettings.headscaleEnable or false) {
  services.headscale = {
    enable = true;
    package = pkgs-unstable.headscale; # v0.28.0 — must match old VPS DB schema
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
        # Split DNS: resolve local domains via pfSense (fallback for non-VPS services)
        nameservers.split = systemSettings.headscaleDnsSplit or {};
        search_domains = systemSettings.headscaleDnsSearchDomains or [];
        magic_dns = true;
        base_domain = "tailnet.${domain}";
        # Push A records for VPS nginx-local services directly to all clients.
        # Clients resolve these locally — no DNS query to pfSense needed.
        # Records auto-generated from systemSettings.nginxLocalServices.
        extra_records = extraDnsRecords;
      };

      # DERP (relay) — self-hosted on VPS (removes dependency on Tailscale Inc's DERP)
      derp = {
        server = {
          enabled = true;
          region_id = 900;
          region_code = "custom";
          region_name = "VPS Self-Hosted";
          stun_listen_addr = "0.0.0.0:3478";
          automatically_add_embedded_derp_region = true;
        };
        urls = [ "https://controlplane.tailscale.com/derpmap/default" ]; # Keep as fallback
        auto_update_enabled = true;
        update_frequency = "24h";
      };

      # Logging
      log = {
        format = "text";
        level = "info";
      };

      # Metrics endpoint for Prometheus scraping
      metrics = {
        listen_addr = "127.0.0.1:9191";
      };

      # Policy — ACL managed via database (headscale policy set --file)
      policy.mode = "database";
    };
  };

  # === TLS termination via nginx + ACME (when domain is configured) ===
  services.nginx = lib.mkIf hasDomain {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
      };
    };
  };

  security.acme = lib.mkIf hasDomain {
    acceptTerms = true;
    defaults.email = acmeEmail;
  };

  # Firewall — port 80 (ACME challenge) + 443 (HTTPS) when nginx is active, otherwise raw port
  networking.firewall.allowedTCPPorts = if hasDomain then [ 80 443 ] else [ port ];
  # STUN/DERP relay port for self-hosted DERP server
  networking.firewall.allowedUDPPorts = [ 3478 ];

  # Headplane (web UI) — DISABLED for now (not tested, security not reviewed)
  # Use CLI only: headscale users list, headscale nodes list, headscale routes list
  # Re-evaluate Headplane after VPN migration is stable and security-audited

  # Prometheus scrape config for Headscale metrics
  services.prometheus.scrapeConfigs = [{
    job_name = "headscale";
    static_configs = [{
      targets = [ "127.0.0.1:9191" ];
      labels = { instance = "headscale"; };
    }];
  }];

  environment.systemPackages = [ pkgs-unstable.headscale ];
}
