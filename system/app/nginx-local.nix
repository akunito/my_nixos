# Nginx Local Access — Tailscale-only vhosts for *.local.akunito.com
#
# Provides direct access to VPS services via Tailscale mesh, bypassing
# Cloudflare Access authentication. Each service gets a subdomain like
# grafana.local.akunito.com, accessible only from Tailscale-registered devices.
#
# Prerequisites:
#   - ACME wildcard cert for *.local.akunito.com (acmeEnable = true in profile)
#   - Cloudflare API token at /etc/secrets/cloudflare-acme
#   - pfSense DNS overrides: *.local.akunito.com → VPS Tailscale IP
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
  # Optional per-service attrs: https (bool), basicAuthFile (path)
  mkVhost = name: cfg: {
    "${name}.${wildcardLocal}" = {
      listenAddresses = [ listenAddr ];
      forceSSL = true;
      useACMEHost = wildcardLocal; # Uses cert from acme.nix
      basicAuthFile = cfg.basicAuthFile or null;
      extraConfig = lib.optionalString ((cfg.maxBodySize or "") != "") ''
        client_max_body_size ${cfg.maxBodySize};
      '';
      locations."/" = {
        proxyPass =
          if cfg.https or false
          then "https://127.0.0.1:${toString cfg.port}"
          else "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
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
