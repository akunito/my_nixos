# Nginx Local Access — Tailscale-only vhosts for *.local.akunito.com
#
# Provides direct access to VPS services via Tailscale mesh, bypassing
# Cloudflare Access authentication. Each service gets a subdomain like
# grafana.local.akunito.com, accessible only from Tailscale-registered devices.
#
# Prerequisites:
#   - ACME wildcard cert for *.local.akunito.com (acmeEnable = true in profile)
#   - Cloudflare API token at /etc/secrets/cloudflare-acme
#   - A pfSense DNS host override PER SERVICE (see below)
#
# DNS IS NOT WILDCARD. The ACME *certificate* is wildcard, which is why adding a
# service here needs no cert work — but resolution does not follow. pfSense
# Unbound answers only names it has an explicit entry for, and an unlisted host
# returns NODATA (the browser shows DNS_PROBE_POSSIBLE), so a new service is
# reachable by IP and dead by name until the record exists. There is no public
# fallback: the old *.local.akunito.com A record pointed at the retired proxy
# LXC (192.168.8.102) and was deleted on 2026-09-04.
#
# The convention is one parent override carrying the rest as aliases: parent id
# 2 is `grafana` -> the VPS Tailscale IP, and every other VPS service hangs off
# it. To add one, POST an alias against that parent and apply:
#
#   curl -sk -X POST -H "x-api-key: $KEY" -H "Content-Type: application/json" \
#     -d '{"parent_id":2,"host":"<name>","domain":"local.akunito.com","descr":"..."}' \
#     https://192.168.8.1/api/v2/services/dns_resolver/host_override/alias
#   curl -sk -X POST -H "x-api-key: $KEY" -H "Content-Type: application/json" \
#     -d '{}' https://192.168.8.1/api/v2/services/dns_resolver/apply
#
# Tailnet clients resolve through the same Unbound: headscaleDnsSplit points
# *.local.akunito.com at 100.64.0.7, which is pfSense itself. One record serves
# LAN and tailnet alike.
#
# Configuration:
#   systemSettings.nginxLocalEnable = true;
#   systemSettings.nginxLocalListenAddress = "100.64.0.6"; # Tailscale IP
#   systemSettings.nginxLocalServices = {
#     grafana = { port = 3002; };
#     status  = { port = 3009; };
#   };

{ config, lib, pkgs, systemSettings, ... }:

let
  listenAddr = systemSettings.nginxLocalListenAddress or "127.0.0.1";
  services = systemSettings.nginxLocalServices or {};
  wildcardLocal = systemSettings.wildcardLocal or "local.example.com";

  # Generate a vhost for each service
  # Optional per-service attrs: https (bool), basicAuthFile (path),
  #                             maxBodySize (str), denyPaths (list of str),
  #                             root (path), publicPort (int)
  #
  # denyPaths returns 403 for a path prefix on the Tailscale vhost only, so a
  # sensitive path stays reachable exclusively through the public Cloudflare
  # Access-protected hostname. Longest-prefix match means these win over "/".
  #
  # root serves static files instead of proxying: pass a Nix path (e.g.
  # ../docs/guides) and it is copied to the store at eval, so the content is
  # immutable and versioned with the flake. `port` is then unused. Content only
  # changes on rebuild — that is the trade for not having a mutable directory
  # on the host. See docs/guides/README.md.
  #
  # publicPort additionally serves the SAME content over plain HTTP on
  # 127.0.0.1:<publicPort>, as a second vhost named "<name>-public". That is the
  # origin a remotely-managed Cloudflare Tunnel points at (cloudflared runs on
  # this host, see system/app/cloudflared.nix), so the site is published on a
  # real public hostname while the Tailscale vhost above keeps serving it inside
  # the tailnet. Deliberately no TLS, no ACME and no basic auth: the hop is
  # loopback-only and cloudflared terminates TLS. Only `root` services support
  # it — a proxy already has a port of its own to point the tunnel at.
  mkPublicVhost = name: cfg:
    lib.optionalAttrs ((cfg ? publicPort) && (cfg ? root)) {
      "${name}-public" = {
        # `listen` (not listenAddresses) because the port must be pinned too.
        listen = [ { addr = "127.0.0.1"; port = cfg.publicPort; ssl = false; } ];
        forceSSL = false;
        enableACME = false;
        default = true; # the only vhost on this port, so name it the default
        extraConfig = lib.optionalString ((cfg.maxBodySize or "") != "") ''
          client_max_body_size ${cfg.maxBodySize};
        '';
        locations."/" = {
          root = cfg.root;
          extraConfig = ''
            index index.html;
          '';
        };
      };
    };

  mkVhost = name: cfg: (mkPublicVhost name cfg) // {
    "${name}.${wildcardLocal}" = {
      listenAddresses = [ listenAddr ];
      forceSSL = true;
      useACMEHost = wildcardLocal; # Uses cert from acme.nix
      basicAuthFile = cfg.basicAuthFile or null;
      extraConfig = lib.optionalString ((cfg.maxBodySize or "") != "") ''
        client_max_body_size ${cfg.maxBodySize};
      '';
      locations = {
        "/" =
          if cfg ? root
          then {
            root = cfg.root;
            extraConfig = ''
              index index.html;
            '';
          }
          else {
            proxyPass =
              if cfg.https or false
              then "https://127.0.0.1:${toString cfg.port}"
              else "http://127.0.0.1:${toString cfg.port}";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
      } // lib.listToAttrs (map (path:
        lib.nameValuePair path { return = "403"; }
      ) (cfg.denyPaths or []));
    };
  };

  # Merge all service vhosts into one attrset
  allVhosts = lib.foldl' (acc: name:
    acc // (mkVhost name services.${name})
  ) {} (builtins.attrNames services);

in
lib.mkIf (systemSettings.nginxLocalEnable or false) {
  # Nginx vhosts for local services — ACME cert provided by acme.nix
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts = allVhosts;
  };
}
