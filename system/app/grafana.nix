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
  secrets = import ../../secrets/domains.nix;
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
        domain = "monitor.${secrets.localDomain}";
        enforce_domain = true;
      };

      # SMTP configuration for alerts (uses local postfix relay at pve-290)
      smtp = {
        enabled = true;
        host = "192.168.8.89:25";
        from_address = secrets.grafanaAlertsFrom;
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
    webExternalUrl = "https://portal.${secrets.localDomain}";
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

    # Alert rules for infrastructure monitoring
    ruleFiles = [
      (pkgs.writeText "container-alerts.yml" (builtins.toJSON {
        groups = [
          {
            name = "container_alerts";
            rules = [
              # Container memory usage approaching limit
              {
                alert = "ContainerMemoryHigh";
                expr = ''(container_memory_usage_bytes{name!=""} / container_spec_memory_limit_bytes{name!=""}) * 100 > 85'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Container {{ $labels.name }} memory usage high";
                  description = "Container {{ $labels.name }} on {{ $labels.instance }} is using {{ $value | printf \"%.1f\" }}% of its memory limit";
                };
              }
              # Container memory critical (>95%)
              {
                alert = "ContainerMemoryCritical";
                expr = ''(container_memory_usage_bytes{name!=""} / container_spec_memory_limit_bytes{name!=""}) * 100 > 95'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Container {{ $labels.name }} memory critical";
                  description = "Container {{ $labels.name }} on {{ $labels.instance }} is using {{ $value | printf \"%.1f\" }}% of its memory limit - OOM risk";
                };
              }
              # Container CPU throttling
              {
                alert = "ContainerCPUThrottling";
                expr = ''rate(container_cpu_cfs_throttled_seconds_total{name!=""}[5m]) > 0.5'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Container {{ $labels.name }} CPU throttled";
                  description = "Container {{ $labels.name }} on {{ $labels.instance }} is being CPU throttled";
                };
              }
              # Container restarting frequently
              {
                alert = "ContainerRestarting";
                expr = ''increase(container_restart_count{name!=""}[1h]) > 3'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Container {{ $labels.name }} restarting";
                  description = "Container {{ $labels.name }} on {{ $labels.instance }} has restarted {{ $value | printf \"%.0f\" }} times in the last hour";
                };
              }
              # Container down (not running)
              {
                alert = "ContainerDown";
                expr = ''absent(container_memory_usage_bytes{name=~".+"}) or (container_last_seen{name!=""} < (time() - 60))'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Container {{ $labels.name }} is down";
                  description = "Container {{ $labels.name }} on {{ $labels.instance }} has been down for more than 2 minutes";
                };
              }
            ];
          }
          {
            name = "node_alerts";
            rules = [
              # High memory usage on host
              {
                alert = "HostMemoryHigh";
                expr = ''(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Host {{ $labels.instance }} memory high";
                  description = "Host {{ $labels.instance }} memory usage is {{ $value | printf \"%.1f\" }}%";
                };
              }
              # High CPU usage on host
              {
                alert = "HostCPUHigh";
                expr = ''100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Host {{ $labels.instance }} CPU high";
                  description = "Host {{ $labels.instance }} CPU usage is {{ $value | printf \"%.1f\" }}%";
                };
              }
              # Disk space low
              {
                alert = "HostDiskSpaceLow";
                expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100 < 15'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Host {{ $labels.instance }} disk space low";
                  description = "Host {{ $labels.instance }} filesystem {{ $labels.mountpoint }} has only {{ $value | printf \"%.1f\" }}% free";
                };
              }
              # Disk space critical
              {
                alert = "HostDiskSpaceCritical";
                expr = ''(node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100 < 5'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Host {{ $labels.instance }} disk space critical";
                  description = "Host {{ $labels.instance }} filesystem {{ $labels.mountpoint }} has only {{ $value | printf \"%.1f\" }}% free";
                };
              }
              # Host down (node exporter not responding)
              {
                alert = "HostDown";
                expr = ''up{job=~".*_node"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Host {{ $labels.instance }} is down";
                  description = "Node exporter on {{ $labels.instance }} has been unreachable for more than 2 minutes";
                };
              }
            ];
          }
          {
            name = "wireguard_alerts";
            rules = [
              # WireGuard interface down
              {
                alert = "WireGuardInterfaceDown";
                expr = ''wireguard_interface_up == 0'';
                "for" = "1m";
                labels.severity = "critical";
                annotations = {
                  summary = "WireGuard interface down on {{ $labels.instance }}";
                  description = "WireGuard interface wg0 is not running on {{ $labels.instance }}";
                };
              }
              # pfSense tunnel disconnected (main home connection)
              {
                alert = "WireGuardPfSenseDisconnected";
                expr = ''wireguard_pfsense_connected == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "WireGuard pfSense tunnel disconnected";
                  description = "The WireGuard tunnel to pfSense (home network) has been down for more than 2 minutes";
                };
              }
              # No active WireGuard peers
              {
                alert = "WireGuardNoPeers";
                expr = ''wireguard_active_peers == 0'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "No active WireGuard peers on {{ $labels.instance }}";
                  description = "WireGuard has no active peer connections for more than 5 minutes";
                };
              }
            ];
          }
        ];
      }))
    ];
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
        sslCertificate = "/etc/nginx/certs/${secrets.localDomain}.crt";
        sslCertificateKey = "/etc/nginx/certs/${secrets.localDomain}.key";
        sslTrustedCertificate = "/etc/nginx/certs/${secrets.localDomain}.crt";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };

      # Prometheus - metrics API (protected with basic auth + IP whitelist)
      "portal.${secrets.localDomain}" = {
        onlySSL = true;
        sslCertificate = "/etc/nginx/certs/${secrets.localDomain}.crt";
        sslCertificateKey = "/etc/nginx/certs/${secrets.localDomain}.key";
        sslTrustedCertificate = "/etc/nginx/certs/${secrets.localDomain}.crt";
        basicAuthFile = "/etc/nginx/auth/prometheus.htpasswd";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
          # IP whitelist: Only allow access from local LAN and WireGuard tunnel
          extraConfig = ''
            allow 192.168.8.0/24;   # Main LAN
            allow 172.26.5.0/24;    # WireGuard tunnel
            allow 127.0.0.1;        # Localhost
            deny all;
          '';
        };
      };
    };
  };
}
