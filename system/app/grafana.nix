# Grafana & Prometheus Monitoring Stack
#
# This module configures a centralized monitoring server with:
# - Grafana (web UI) on port 3002
# - Prometheus (metrics database) on port 9090
# - Local Node Exporter on port 9091 (for monitoring the monitoring server itself)
#
# Remote targets are configured via systemSettings.prometheusRemoteTargets:
# [
#   { name = "lxc_home"; host = "192.168.8.80"; nodePort = 9100; cadvisorPort = 9092; }
#   ...
# ]
#
# Accessed via nginx reverse proxy with SSL:
# - Grafana: https://monitor.akunito.org.es (port 8043)
# - Prometheus: https://portal.akunito.org.es (port 8043, with basic auth)

{ pkgs, lib, systemSettings, config, ... }:

let
  remoteTargets = systemSettings.prometheusRemoteTargets or [];

  # Build scrape configs for remote Node Exporters
  remoteNodeScrapeConfigs = map (target: {
    job_name = "${target.name}_node";
    static_configs = [{
      targets = [ "${target.host}:${toString target.nodePort}" ];
      labels = {
        instance = target.name;
        container = target.name;
      };
    }];
  }) remoteTargets;

  # Build scrape configs for remote cAdvisors (filter out targets with null cadvisorPort)
  remoteCadvisorScrapeConfigs = map (target: {
    job_name = "${target.name}_docker";
    static_configs = [{
      targets = [ "${target.host}:${toString target.cadvisorPort}" ];
      labels = {
        instance = target.name;
        container = target.name;
      };
    }];
  }) (builtins.filter (t: t.cadvisorPort != null) remoteTargets);

  # Local scrape configs (for the monitoring server itself)
  localScrapeConfigs = [
    {
      job_name = "monitoring_node";
      static_configs = [{
        targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
        labels = {
          instance = "monitoring";
          container = "monitoring";
        };
      }];
    }
  ];

in
{
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3002;
        protocol = "http";
        domain = "monitor.akunito.org.es";
        enforce_domain = true;
      };

      # SMTP configuration for alerts (uses local postfix relay at pve-290)
      smtp = {
        enabled = true;
        host = "192.168.8.89:25";
        from_address = "alerts@akunito.com";
        from_name = "Grafana Monitoring";
        skip_verify = true;  # Local relay, no TLS
      };

      # Unified alerting (Grafana 9+) - replaces legacy alerting
      unified_alerting = {
        enabled = true;
      };
    };
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    webExternalUrl = "https://portal.akunito.org.es";
    globalConfig.scrape_interval = "15s";

    # Local Node Exporter for monitoring server system metrics
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
          "processes"
        ];
        port = 9091; # Different port from remote exporters to avoid confusion
      };
    };

    # Combine local + remote scrape configs
    scrapeConfigs = localScrapeConfigs ++ remoteNodeScrapeConfigs ++ remoteCadvisorScrapeConfigs;
  };

  # Nginx reverse proxy with SSL
  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 80;
    defaultSSLListenPort = 443;

    virtualHosts = {
      # Grafana - main monitoring UI
      "${config.services.grafana.settings.server.domain}" = {
        onlySSL = true;
        sslCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        sslCertificateKey = "/etc/nginx/certs/akunito.org.es.key";
        sslTrustedCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };

      # Prometheus - metrics API (protected with basic auth)
      "portal.akunito.org.es" = {
        onlySSL = true;
        sslCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        sslCertificateKey = "/etc/nginx/certs/akunito.org.es.key";
        sslTrustedCertificate = "/etc/nginx/certs/akunito.org.es.crt";
        basicAuthFile = "/etc/nginx/auth/prometheus.htpasswd";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };
}
