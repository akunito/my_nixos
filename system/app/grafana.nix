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
# Accessed via nginx reverse proxy:
# - Grafana (local): https://grafana.local.akunito.com (port 443, SSL)
# - Grafana (public): https://grafana.akunito.com (via Cloudflare Tunnel, port 80 → nginx)
# - Prometheus: https://prometheus.local.akunito.com (port 443, SSL, with basic auth + IP whitelist)

{ pkgs, lib, systemSettings, config, ... }:

let
  secrets = import ../../secrets/domains.nix;
  remoteTargets = systemSettings.prometheusRemoteTargets or [];
  appTargets = systemSettings.prometheusAppTargets or [];

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

  # Build scrape configs for application exporters (exportarr, etc.)
  appScrapeConfigs = map (target: {
    job_name = "${target.name}_app";
    static_configs = [{
      targets = [ "${target.host}:${toString target.port}" ];
      labels = {
        instance = target.name;
        app = target.name;
      };
    }];
  }) appTargets;

in
{
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3002;
        protocol = "http";
        domain = "grafana.${secrets.wildcardLocal}";
        # Allow both local and public domains (local via nginx SSL, public via Cloudflare Tunnel)
        enforce_domain = false;
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

    # Dashboard and data source provisioning
    provision = {
      enable = true;

      # Data source provisioning (fixed UID for dashboard references)
      datasources.settings.datasources = [{
        name = "Prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:${toString config.services.prometheus.port}";
        isDefault = true;
        editable = false;
        uid = "prometheus";
      }];

      # Dashboard provisioning from /etc/grafana-dashboards
      dashboards.settings.providers = [{
        name = "Infrastructure";
        type = "file";
        disableDeletion = false;
        allowUiUpdates = true;  # Allow editing provisioned dashboards in UI (export to repo to persist)
        options = {
          path = "/etc/grafana-dashboards";
          foldersFromFilesStructure = true;
        };
      }];

      # Alert contact points provisioning (email notifications)
      alerting.contactPoints.settings = {
        apiVersion = 1;
        contactPoints = [{
          orgId = 1;
          name = "email-alerts";
          receivers = [{
            uid = "email-receiver";
            type = "email";
            settings = {
              addresses = secrets.alertEmail;
              singleEmail = true;
            };
          }];
        }];
      };

      # Alert notification policies (route all alerts to email contact point)
      alerting.policies.settings = {
        apiVersion = 1;
        policies = [{
          orgId = 1;
          receiver = "email-alerts";
          group_by = ["alertname" "severity"];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
        }];
      };
    };
  };

  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    webExternalUrl = "https://prometheus.${secrets.wildcardLocal}";
    globalConfig.scrape_interval = "15s";

    # Enable admin API for deleting stale time series
    extraFlags = [
      "--web.enable-admin-api"
      "--web.enable-lifecycle"
    ];

    # Local Node Exporter for monitoring server system metrics
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
          "processes"
          "textfile"  # Custom metrics from textfiles (auto-update status, backup status)
        ];
        extraFlags = [
          "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile"
        ];
        port = 9091; # Different port from remote exporters to avoid confusion
      };
    };

    # Combine local + remote + app scrape configs
    scrapeConfigs = localScrapeConfigs ++ remoteNodeScrapeConfigs ++ remoteCadvisorScrapeConfigs ++ appScrapeConfigs;

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
          {
            name = "backup_alerts";
            rules = [
              # Backup too old (more than 25 hours - allows for daily backup window)
              {
                alert = "BackupTooOld";
                expr = ''backup_age_seconds{repo="home"} > 90000'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "Backup is too old on {{ $labels.instance }}";
                  description = "Last backup on {{ $labels.instance }} was {{ $value | humanizeDuration }} ago";
                };
              }
              # Backup critically old (more than 48 hours)
              {
                alert = "BackupCriticallyOld";
                expr = ''backup_age_seconds{repo="home"} > 172800'';
                "for" = "1h";
                labels.severity = "critical";
                annotations = {
                  summary = "Backup is critically old on {{ $labels.instance }}";
                  description = "Last backup on {{ $labels.instance }} was {{ $value | humanizeDuration }} ago - immediate attention required";
                };
              }
              # Backup repository unhealthy
              {
                alert = "BackupRepositoryUnhealthy";
                expr = ''backup_repository_healthy == 0'';
                "for" = "15m";
                labels.severity = "critical";
                annotations = {
                  summary = "Backup repository unhealthy on {{ $labels.instance }}";
                  description = "Cannot access backup repository on {{ $labels.instance }} - check restic configuration";
                };
              }
            ];
          }
          {
            name = "arr_alerts";
            rules = [
              # Sonarr queue stuck (items in queue for too long)
              {
                alert = "SonarrQueueStuck";
                expr = ''sonarr_queue_total > 0 and increase(sonarr_episode_downloaded_total[6h]) == 0'';
                "for" = "6h";
                labels.severity = "warning";
                annotations = {
                  summary = "Sonarr queue appears stuck";
                  description = "Sonarr has {{ $value }} items in queue but no downloads completed in 6 hours";
                };
              }
              # Radarr queue stuck
              {
                alert = "RadarrQueueStuck";
                expr = ''radarr_queue_total > 0 and increase(radarr_movie_downloaded_total[6h]) == 0'';
                "for" = "6h";
                labels.severity = "warning";
                annotations = {
                  summary = "Radarr queue appears stuck";
                  description = "Radarr has {{ $value }} items in queue but no downloads completed in 6 hours";
                };
              }
              # Sonarr health issues
              {
                alert = "SonarrHealthIssue";
                expr = ''sonarr_system_health_issues > 0'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "Sonarr has health issues";
                  description = "Sonarr is reporting {{ $value }} health issues - check the Sonarr UI";
                };
              }
              # Radarr health issues
              {
                alert = "RadarrHealthIssue";
                expr = ''radarr_system_health_issues > 0'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "Radarr has health issues";
                  description = "Radarr is reporting {{ $value }} health issues - check the Radarr UI";
                };
              }
              # Prowlarr health issues
              {
                alert = "ProwlarrHealthIssue";
                expr = ''prowlarr_system_health_issues > 0'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "Prowlarr has health issues";
                  description = "Prowlarr is reporting {{ $value }} health issues - check the Prowlarr UI";
                };
              }
              # Exportarr target down
              {
                alert = "ExportarrTargetDown";
                expr = ''up{job=~".*_app"} == 0'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Exportarr target {{ $labels.instance }} is down";
                  description = "Cannot scrape metrics from {{ $labels.instance }} - check if the app and exporter are running";
                };
              }
            ];
          }
          {
            name = "autoupdate_alerts";
            rules = [
              # NixOS system auto-update failed
              {
                alert = "NixOSAutoUpdateFailed";
                expr = ''nixos_autoupdate_system_status == 0'';
                "for" = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "NixOS auto-update failed on {{ $labels.hostname }}";
                  description = "System auto-update failed on {{ $labels.hostname }} - check logs with 'journalctl -u nixos-autoupgrade'";
                };
              }
              # NixOS system auto-update stale (no update in 8+ days)
              {
                alert = "NixOSAutoUpdateStale";
                expr = ''(time() - nixos_autoupdate_system_last_success) > 691200'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "NixOS auto-update stale on {{ $labels.hostname }}";
                  description = "Last successful system update on {{ $labels.hostname }} was {{ $value | humanizeDuration }} ago";
                };
              }
              # Home-manager auto-update failed
              {
                alert = "HomeManagerAutoUpdateFailed";
                expr = ''nixos_autoupdate_user_status == 0'';
                "for" = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "Home-manager auto-update failed on {{ $labels.hostname }}";
                  description = "User auto-update failed on {{ $labels.hostname }} - check logs with 'journalctl -u home-manager-autoupgrade'";
                };
              }
            ];
          }
          {
            name = "pve_backup_alerts";
            rules = [
              # PVE backup failed
              {
                alert = "PVEBackupFailed";
                expr = ''pve_backup_status == 0'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "Proxmox backup failed for {{ $labels.name }}";
                  description = "Most recent backup for VM/LXC {{ $labels.name }} ({{ $labels.vmid }}) failed";
                };
              }
              # PVE backup too old (more than 7 days)
              {
                alert = "PVEBackupTooOld";
                expr = ''pve_backup_age_seconds > 604800'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "Proxmox backup too old for {{ $labels.name }}";
                  description = "Last successful backup for {{ $labels.name }} ({{ $labels.vmid }}) was {{ $value | humanizeDuration }} ago";
                };
              }
              # PVE backup critically old (more than 14 days)
              {
                alert = "PVEBackupCriticallyOld";
                expr = ''pve_backup_age_seconds > 1209600'';
                "for" = "1h";
                labels.severity = "critical";
                annotations = {
                  summary = "Proxmox backup critically old for {{ $labels.name }}";
                  description = "Last successful backup for {{ $labels.name }} ({{ $labels.vmid }}) was {{ $value | humanizeDuration }} ago - immediate attention required";
                };
              }
            ];
          }
        ];
      }))
    ];
  };

  # Create textfile directory for custom metrics (auto-update status, backup status)
  # Mode 0775 allows group write access for user update scripts (wheel group)
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
  ];

  # Copy dashboard JSON files to /etc/grafana-dashboards for provisioning
  environment.etc = {
    # Custom dashboards
    "grafana-dashboards/custom/wireguard.json".source = ./grafana-dashboards/custom/wireguard.json;
    "grafana-dashboards/custom/truenas.json".source = ./grafana-dashboards/custom/truenas.json;
    "grafana-dashboards/custom/pfsense.json".source = ./grafana-dashboards/custom/pfsense.json;
    "grafana-dashboards/custom/media-stack.json".source = ./grafana-dashboards/custom/media-stack.json;
    "grafana-dashboards/custom/infrastructure-status.json".source = ./grafana-dashboards/custom/infrastructure-status.json;
    "grafana-dashboards/custom/infrastructure-overview.json".source = ./grafana-dashboards/custom/infrastructure-overview.json;
    # Community dashboards
    "grafana-dashboards/community/node-exporter-full.json".source = ./grafana-dashboards/community/node-exporter-full.json;
    "grafana-dashboards/community/docker-cadvisor.json".source = ./grafana-dashboards/community/docker-cadvisor.json;
    "grafana-dashboards/community/blackbox-exporter.json".source = ./grafana-dashboards/community/blackbox-exporter.json;
    "grafana-dashboards/community/proxmox-ve.json".source = ./grafana-dashboards/community/proxmox-ve.json;
    "grafana-dashboards/community/docker-system-monitoring.json".source = ./grafana-dashboards/community/docker-system-monitoring.json;
  };

  # Nginx reverse proxy with SSL
  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 80;
    defaultSSLListenPort = 443;

    virtualHosts = {
      # Grafana - main monitoring UI (local access with SSL)
      "${config.services.grafana.settings.server.domain}" = {
        onlySSL = true;
        sslCertificate = "/mnt/shared-certs/${secrets.wildcardLocal}.crt";
        sslCertificateKey = "/mnt/shared-certs/${secrets.wildcardLocal}.key";
        sslTrustedCertificate = "/mnt/shared-certs/${secrets.wildcardLocal}.crt";
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };

      # Grafana - public access via Cloudflare Tunnel (HTTP - TLS terminated by Cloudflare)
      "grafana.${secrets.publicDomain}" = {
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };

      # Prometheus - metrics API (protected with basic auth + IP whitelist)
      "prometheus.${secrets.wildcardLocal}" = {
        onlySSL = true;
        sslCertificate = "/mnt/shared-certs/${secrets.wildcardLocal}.crt";
        sslCertificateKey = "/mnt/shared-certs/${secrets.wildcardLocal}.key";
        sslTrustedCertificate = "/mnt/shared-certs/${secrets.wildcardLocal}.crt";
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
