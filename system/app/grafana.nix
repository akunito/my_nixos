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

{ pkgs, lib, systemSettings, userSettings, config, ... }:

let
  # Domain secrets are passed through systemSettings by each profile
  wildcardLocal = systemSettings.wildcardLocal or "local.example.com";
  publicDomain = systemSettings.publicDomain or "example.com";
  grafanaAlertsFrom = systemSettings.grafanaAlertsFrom or systemSettings.notificationFromEmail or "alerts@example.com";
  alertEmail = systemSettings.notificationToEmail or "admin@example.com";
  remoteTargets = systemSettings.prometheusRemoteTargets or [];
  appTargets = systemSettings.prometheusAppTargets or [];
  localSslEnable = systemSettings.grafanaLocalSslEnable or true;

  # Pocket ID OIDC login (auth.akunito.com). Enabled when a client id is provided.
  oauthClientId = systemSettings.grafanaOauthClientId or "";
  oauthEnabled = oauthClientId != "";

  # Build scrape configs for remote Node Exporters
  # node = which machine a series belongs to (alert routing groups and mutes on
  # it); role = always_on|roaming decides whether HostDown applies.
  remoteNodeScrapeConfigs = map (target: {
    job_name = "${target.name}_node";
    static_configs = [{
      targets = [ "${target.host}:${toString target.nodePort}" ];
      labels = {
        instance = target.name;
        container = target.name;
        node = target.name;
        role = target.role or "roaming";
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
        node = target.name;
        role = target.role or "roaming";
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
          node = "vps";
          role = "always_on";
        };
      }];
    }
  ] ++ lib.optionals (systemSettings.prometheusExporterCadvisorEnable or false) [
    {
      job_name = "vps_docker";
      static_configs = [{
        targets = [ "127.0.0.1:${toString (systemSettings.prometheusCadvisorPort or 9092)}" ];
        labels = {
          instance = "vps";
          node = "vps";
          role = "always_on";
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
        # exporters that live on another machine say so (node = "nas" for exportarr)
        node = target.node or "vps";
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
        domain = "grafana.${wildcardLocal}";
        # Allow both local and public domains (local via nginx SSL, public via Cloudflare Tunnel)
        enforce_domain = false;
        # Canonical external URL — needed so the OAuth redirect_uri is correct.
        # Use the public domain (reachable over Tailscale hairpin + internet).
        root_url = lib.mkIf oauthEnabled "https://grafana.${publicDomain}";
      };

      # SMTP configuration for alerts (uses local postfix relay)
      smtp = {
        enabled = true;
        host = systemSettings.smtpRelayHost or "192.168.8.89:25";
        from_address = grafanaAlertsFrom;
        from_name = "Grafana Monitoring";
        skip_verify = true;  # Local relay, no TLS
      };

      # Unified alerting (Grafana 9+) - replaces legacy alerting
      unified_alerting = {
        enabled = true;
      };

      # Allow unsigned community plugins (SQLite datasource for finance data)
      plugins = {
        allow_loading_unsigned_plugins = "frser-sqlite-datasource";
      };

      # Enable public dashboards feature (Grafana 9.1+)
      # Allows creating shareable, read-only versions of specific dashboards
      # without exposing the full Grafana instance
      feature_toggles = {
        publicDashboards = true;
      };

      # Security settings for embedding dashboards in external sites (e.g., portfolio, control panel)
      security = {
        allow_embedding = true;
        # Allow cookies to work in iframes (required for authentication in embedded dashboards)
        cookie_samesite = "none";
        cookie_secure = true;
      };

      # Anonymous access for embedded dashboard viewing (read-only)
      # Users are already authenticated via control panel's HTTP Basic Auth
      "auth.anonymous" = {
        enabled = true;
        org_name = "Main Org.";
        org_role = "Viewer";  # Read-only access
      };

      # Pocket ID OIDC login (auth.akunito.com). Built-in admin login stays as fallback.
      # Client secret read from /etc/secrets at runtime (not baked into grafana.ini).
      "auth.generic_oauth" = lib.mkIf oauthEnabled {
        enabled = true;
        name = "Pocket ID";
        icon = "signin";
        client_id = oauthClientId;
        client_secret = "$__file{/etc/secrets/grafana-oauth-client-secret}";
        scopes = "openid email profile";
        auth_url = "https://auth.${publicDomain}/authorize";
        token_url = "https://auth.${publicDomain}/api/oidc/token";
        api_url = "https://auth.${publicDomain}/api/oidc/userinfo";
        use_pkce = true;
        login_attribute_path = "preferred_username";
        email_attribute_path = "email";
        name_attribute_path = "name";
        allow_sign_up = true;
        # 2-person trusted setup: OAuth logins get org Admin.
        role_attribute_path = "'Admin'";
      };
    };

    # Dashboard and data source provisioning
    provision = {
      enable = true;

      # Data source provisioning (fixed UID for dashboard references)
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
          editable = false;
          uid = "prometheus";
        }
        {
          name = "Finance SQLite";
          type = "frser-sqlite-datasource";
          jsonData = {
            # URI format with immutable=1 for read-only access to WAL-mode DB
            path = "file:/home/${userSettings.username}/.openclaw/finance-data/vaultkeeper.db?immutable=1";
          };
          editable = false;
          uid = "finance-sqlite";
        }
      ];

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

      # Contact points only apply to GRAFANA-MANAGED rules, of which there are
      # none — every rule here is a Prometheus rule delivered by Alertmanager
      # (system/app/alertmanager.nix, which also owns the Telegram routing).
      # The email contact point stays for anything created in the UI.
      alerting.contactPoints.settings = {
        apiVersion = 1;
        contactPoints = [
          {
            orgId = 1;
            name = "email-alerts";
            receivers = [{
              uid = "email-receiver";
              type = "email";
              settings = {
                addresses = alertEmail;
                singleEmail = true;
              };
            }];
          }
        ];
      };

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
    webExternalUrl = "https://prometheus.${wildcardLocal}";
    globalConfig.scrape_interval = "15s";

    # Enable admin API for deleting stale time series
    extraFlags = [
      "--web.enable-admin-api"
      "--web.enable-lifecycle"
      "--storage.tsdb.retention.time=90d"
      "--query.timeout=10s"
      "--query.max-samples=5000000"
      "--query.max-concurrency=4"
    ];

    # Local Node Exporter for monitoring server system metrics
    exporters = {
      node = {
        enable = true;
        listenAddress = "127.0.0.1";
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
                expr = ''(container_memory_working_set_bytes{name!=""} / (container_spec_memory_limit_bytes{name!=""} > 0)) * 100 > 85'';
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
                expr = ''(container_memory_working_set_bytes{name!=""} / (container_spec_memory_limit_bytes{name!=""} > 0)) * 100 > 95'';
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
                # > Prometheus' 5-minute staleness window: after a restart/label change the
                # old series linger that long and would otherwise fire a false critical
                "for" = "6m";
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
              # Host down — only for nodes that are supposed to be up 24/7.
              # Laptops/desktops (role=roaming) are off most of the day; the NAS is
              # always_on but muted 23:00-16:05 by Alertmanager while it sleeps.
              {
                alert = "HostDown";
                expr = ''up{job=~".*_node", role="always_on"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Host {{ $labels.instance }} is down";
                  description = "Node exporter on {{ $labels.instance }} has been unreachable for more than 2 minutes";
                };
              }
              # Host memory critically low (<1GB available)
              {
                alert = "HostMemoryCritical";
                expr = ''node_memory_MemAvailable_bytes < 1073741824'';
                "for" = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Host {{ $labels.instance }} memory critically low";
                  description = "Host {{ $labels.instance }} has less than 1GB available memory";
                };
              }
              # TLS certificate expiring soon (<7 days)
              {
                alert = "TLSCertExpiringSoon";
                expr = ''probe_ssl_earliest_cert_expiry - time() < 7 * 86400'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "TLS certificate expiring soon for {{ $labels.instance }}";
                  description = "Certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }}";
                };
              }
              # TLS certificate expiring critical (<3 days)
              {
                alert = "TLSCertExpiryCritical";
                expr = ''probe_ssl_earliest_cert_expiry - time() < 3 * 86400'';
                "for" = "30m";
                labels.severity = "critical";
                annotations = {
                  summary = "TLS certificate expiring in under 3 days for {{ $labels.instance }}";
                  description = "Certificate for {{ $labels.instance }} expires in {{ $value | humanizeDuration }} - immediate renewal needed";
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
                expr = ''backup_age_seconds{repo=~"home_nfs|home_legacy"} > 90000'';
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
                expr = ''backup_age_seconds{repo=~"home_nfs|home_legacy"} > 172800'';
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
              # pfSense backup stale (>36h)
              {
                alert = "PfsenseBackupStale";
                expr = ''pfsense_backup_age_seconds > 129600'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "pfSense backup is stale";
                  description = "pfSense config backup is {{ $value | humanizeDuration }} old (threshold: 36h)";
                };
              }
              # pfSense backup critical (>72h)
              {
                alert = "PfsenseBackupCritical";
                expr = ''pfsense_backup_age_seconds > 259200'';
                "for" = "1h";
                labels.severity = "critical";
                annotations = {
                  summary = "pfSense backup is critically old";
                  description = "pfSense config backup is {{ $value | humanizeDuration }} old (threshold: 72h) - immediate attention required";
                };
              }
              # pfSense backup missing/failed
              {
                alert = "PfsenseBackupMissing";
                expr = ''pfsense_backup_status == 0'';
                "for" = "15m";
                labels.severity = "critical";
                annotations = {
                  summary = "pfSense backup failed";
                  description = "pfSense config backup job failed - check SSH connectivity to pfSense";
                };
              }
              # NAS VPS restic backup stale (>36h)
              {
                alert = "NasVpsBackupStale";
                expr = ''nas_backup_age_seconds{dataset=~"vps_.*"} > 129600'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS VPS backup stale: {{ $labels.dataset }}";
                  description = "Restic repo {{ $labels.dataset }} is {{ $value | humanizeDuration }} old (threshold: 36h)";
                };
              }
              # NAS workstation restic backup stale (>30h)
              {
                alert = "NasWorkstationBackupStale";
                expr = ''nas_backup_age_seconds{dataset=~"desk_.*|x13_.*"} > 108000'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS workstation backup stale: {{ $labels.dataset }}";
                  description = "Restic repo {{ $labels.dataset }} is {{ $value | humanizeDuration }} old (threshold: 30h)";
                };
              }
              # NAS backup missing (any repo)
              {
                alert = "NasBackupMissing";
                expr = ''nas_backup_status == 0'';
                "for" = "15m";
                labels.severity = "critical";
                annotations = {
                  summary = "NAS backup repo missing: {{ $labels.dataset }}";
                  description = "Cannot find snapshot files in restic repo {{ $labels.dataset }} on NAS";
                };
              }
              # NAS offsite backup stale (VPS pulls from NAS, >36h)
              {
                alert = "NasOffsiteBackupStale";
                expr = ''(time() - nas_offsite_backup_last_success) > 129600'';
                "for" = "1h";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS offsite backup stale: {{ $labels.exported_job }}";
                  description = "NAS→VPS offsite backup {{ $labels.exported_job }} last succeeded {{ $value | humanizeDuration }} ago (threshold: 36h)";
                };
              }
              # NAS offsite backup failed
              {
                alert = "NasOffsiteBackupFailed";
                expr = ''nas_offsite_backup_status == 0'';
                "for" = "15m";
                labels.severity = "critical";
                annotations = {
                  summary = "NAS offsite backup failed: {{ $labels.exported_job }}";
                  description = "NAS→VPS offsite backup {{ $labels.exported_job }} failed - check systemd journal for nas-backup-{{ $labels.exported_job }}";
                };
              }
              # NAS offsite backup has rsync warnings (silent coverage gap)
              {
                alert = "NasOffsiteBackupRsyncWarnings";
                expr = ''nas_offsite_backup_rsync_warnings > 0'';
                "for" = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS offsite backup {{ $labels.exported_job }} has rsync warnings";
                  description = "{{ $value }} rsync_dir call(s) in nas-backup-{{ $labels.exported_job }} hit non-fatal errors. Restic snapshot succeeded but some source paths were not captured. Check journal for 'WARNING: rsync ... had errors'.";
                };
              }
            ];
          }
          {
            # NAS storage & health alerts (migrated from prometheus-graphite.nix)
            # Uses node_exporter metrics instead of Graphite
            name = "nas_alerts";
            rules = [
              # ZFS pool capacity warning (>80%)
              {
                alert = "NASPoolCapacityWarning";
                expr = ''(1 - node_filesystem_avail_bytes{job="nas_node",fstype="zfs",mountpoint=~"/mnt/(ssdpool|extpool)"} / node_filesystem_size_bytes{job="nas_node",fstype="zfs",mountpoint=~"/mnt/(ssdpool|extpool)"}) * 100 > 80'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS pool {{ $labels.mountpoint }} capacity warning";
                  description = "Pool {{ $labels.mountpoint }} is at {{ $value | printf \"%.1f\" }}% capacity";
                };
              }
              # ZFS pool capacity critical (>90%)
              {
                alert = "NASPoolCapacityCritical";
                expr = ''(1 - node_filesystem_avail_bytes{job="nas_node",fstype="zfs",mountpoint=~"/mnt/(ssdpool|extpool)"} / node_filesystem_size_bytes{job="nas_node",fstype="zfs",mountpoint=~"/mnt/(ssdpool|extpool)"}) * 100 > 90'';
                "for" = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "NAS pool {{ $labels.mountpoint }} capacity critical";
                  description = "Pool {{ $labels.mountpoint }} is at {{ $value | printf \"%.1f\" }}% capacity - immediate attention required";
                };
              }
              # ZFS pool unhealthy
              {
                alert = "NASPoolUnhealthy";
                expr = ''node_zfs_zpool_state{job="nas_node",state="online"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "NAS ZFS pool {{ $labels.zpool }} unhealthy";
                  description = "Pool {{ $labels.zpool }} is not ONLINE - check pool status immediately";
                };
              }
              # Disk temperature warning (>45C)
              {
                alert = "NASDiskTempWarning";
                expr = ''node_hwmon_temp_celsius{job="nas_node",chip=~"drivetemp.*"} > 45'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS disk temperature warning ({{ $labels.chip }})";
                  description = "Disk {{ $labels.chip }} temperature is {{ $value | printf \"%.1f\" }}C";
                };
              }
              # Disk temperature critical (>55C)
              {
                alert = "NASDiskTempCritical";
                expr = ''node_hwmon_temp_celsius{job="nas_node",chip=~"drivetemp.*"} > 55'';
                "for" = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "NAS disk temperature critical ({{ $labels.chip }})";
                  description = "Disk {{ $labels.chip }} temperature is {{ $value | printf \"%.1f\" }}C - risk of hardware damage";
                };
              }
              # NAS memory high (>90%)
              {
                alert = "NASMemoryHigh";
                expr = ''(1 - node_memory_MemAvailable_bytes{job="nas_node"} / node_memory_MemTotal_bytes{job="nas_node"}) * 100 > 90'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "NAS memory usage high";
                  description = "NAS memory usage is at {{ $value | printf \"%.1f\" }}%";
                };
              }
            ];
          }
          {
            name = "infrastructure_alerts";
            rules = [
              # Systemd service failed on any monitored host
              {
                alert = "SystemdServiceFailed";
                expr = ''node_systemd_unit_state{state="failed"} == 1'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Systemd unit failed on {{ $labels.instance }}";
                  description = "Unit {{ $labels.name }} is in failed state on {{ $labels.instance }}";
                };
              }
              # Blackbox HTTP probe failure
              {
                alert = "BlackboxProbeFailed";
                expr = ''probe_success == 0'';
                "for" = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Probe failed: {{ $labels.instance }}";
                  description = "HTTP/ICMP probe to {{ $labels.instance }} has been failing for 5 minutes";
                };
              }
              # High swap usage (memory pressure indicator)
              {
                alert = "HostSwapUsageHigh";
                expr = ''(node_memory_SwapTotal_bytes > 0) and ((node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / node_memory_SwapTotal_bytes * 100 > 50)'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Host {{ $labels.instance }} swap usage high";
                  description = "Swap usage on {{ $labels.instance }} is {{ $value | printf \"%.1f\" }}% (threshold: 50%)";
                };
              }
              # File descriptor exhaustion risk
              {
                alert = "HostFileDescriptorsHigh";
                expr = ''node_filefd_allocated / node_filefd_maximum * 100 > 80'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Host {{ $labels.instance }} file descriptors high";
                  description = "File descriptor usage on {{ $labels.instance }} is {{ $value | printf \"%.1f\" }}% (threshold: 80%)";
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
            name = "matrix_alerts";
            rules = [
              # Synapse down
              {
                alert = "SynapseDown";
                expr = ''up{job="synapse_app"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Matrix Synapse is down";
                  description = "Cannot scrape Synapse metrics - Matrix server may be down";
                };
              }
              # Synapse high memory usage
              {
                alert = "SynapseHighMemory";
                expr = ''synapse_process_resident_memory_bytes > 2e9'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "Synapse using high memory";
                  description = "Matrix Synapse is using {{ $value | humanize1024 }} of memory";
                };
              }
              # Federation queue backing up
              {
                alert = "SynapseFederationQueueHigh";
                expr = ''synapse_federation_send_events_queue > 1000'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Federation queue backing up";
                  description = "Matrix federation queue has {{ $value }} events pending";
                };
              }
              # High request latency
              {
                alert = "SynapseHighLatency";
                expr = ''histogram_quantile(0.99, rate(synapse_http_server_response_time_seconds_bucket[5m])) > 5'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Synapse request latency high";
                  description = "99th percentile request latency is {{ $value | printf \"%.2f\" }} seconds";
                };
              }
            ];
          }
          {
            name = "database_alerts";
            rules = [
              # PostgreSQL exporter down
              {
                alert = "PostgreSQLDown";
                expr = ''up{job="postgresql_app"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "PostgreSQL exporter is down";
                  description = "Cannot scrape PostgreSQL metrics from {{ $labels.instance }} - database server may be down";
                };
              }
              # PostgreSQL too many connections
              {
                alert = "PostgreSQLConnectionsHigh";
                expr = ''(pg_stat_activity_count / pg_settings_max_connections) * 100 > 80'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "PostgreSQL connections high";
                  description = "PostgreSQL is using {{ $value | printf \"%.1f\" }}% of max connections";
                };
              }
              # PostgreSQL replication lag (if replicas exist)
              {
                alert = "PostgreSQLReplicationLag";
                expr = ''pg_replication_lag > 30'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "PostgreSQL replication lag";
                  description = "PostgreSQL replication is {{ $value | printf \"%.0f\" }} seconds behind";
                };
              }
              # MariaDB exporter down
              {
                alert = "MariaDBDown";
                expr = ''up{job="mariadb_app"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "MariaDB exporter is down";
                  description = "Cannot scrape MariaDB metrics from {{ $labels.instance }} - database server may be down";
                };
              }
              # MariaDB too many connections
              {
                alert = "MariaDBConnectionsHigh";
                expr = ''(mysql_global_status_threads_connected / mysql_global_variables_max_connections) * 100 > 80'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "MariaDB connections high";
                  description = "MariaDB is using {{ $value | printf \"%.1f\" }}% of max connections";
                };
              }
              # Redis exporter down
              {
                alert = "RedisDown";
                expr = ''up{job="redis_app"} == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "Redis exporter is down";
                  description = "Cannot scrape Redis metrics from {{ $labels.instance }} - Redis server may be down";
                };
              }
              # Redis memory usage high
              {
                alert = "RedisMemoryHigh";
                expr = ''(redis_memory_used_bytes / redis_memory_max_bytes) * 100 > 90'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Redis memory usage high";
                  description = "Redis is using {{ $value | printf \"%.1f\" }}% of max memory";
                };
              }
              # Redis connected clients high
              {
                alert = "RedisClientsHigh";
                expr = ''redis_connected_clients > 500'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Redis connected clients high";
                  description = "Redis has {{ $value | printf \"%.0f\" }} connected clients";
                };
              }
              # Database backup failed (from textfile exporter)
              # Daily backups - alert if failed or stale (>26 hours since last success)
              {
                alert = "PostgreSQLDailyBackupFailed";
                expr = ''postgresql_backup_daily_status == 0 or (time() - postgresql_backup_daily_last_success_timestamp) > 93600'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "PostgreSQL daily backup failed or stale";
                  description = "PostgreSQL daily backup job failed or hasn't run in over 26 hours";
                };
              }
              {
                alert = "MariaDBDailyBackupFailed";
                expr = ''mariadb_backup_daily_status == 0 or (time() - mariadb_backup_daily_last_success_timestamp) > 93600'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "MariaDB daily backup failed or stale";
                  description = "MariaDB daily backup job failed or hasn't run in over 26 hours";
                };
              }
              # Hourly backups - alert if stale (>2 hours since last success)
              {
                alert = "PostgreSQLHourlyBackupStale";
                expr = ''(time() - postgresql_backup_hourly_last_success_timestamp) > 7200'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "PostgreSQL hourly backup stale";
                  description = "PostgreSQL hourly backup hasn't run in over 2 hours";
                };
              }
              {
                alert = "MariaDBHourlyBackupStale";
                expr = ''(time() - mariadb_backup_hourly_last_success_timestamp) > 7200'';
                "for" = "30m";
                labels.severity = "warning";
                annotations = {
                  summary = "MariaDB hourly backup stale";
                  description = "MariaDB hourly backup hasn't run in over 2 hours";
                };
              }
            ];
          }
          {
            # Host health from prometheus-host-health.nix textfiles + tailscale.nix
            name = "host_health_alerts";
            rules = [
              {
                alert = "DockerDaemonDown";
                expr = ''host_docker_daemon_up == 0'';
                "for" = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "Docker {{ $labels.mode }} daemon down on {{ $labels.node }}";
                  description = "The {{ $labels.mode }} docker daemon on {{ $labels.node }} is not active — every container it runs is down";
                };
              }
              # Failed units on hosts WITHOUT a native systemd collector (NAS: docker
              # node-exporter). "unless" drops nodes where SystemdServiceFailed already
              # sees the same unit, so a unit never alerts twice.
              {
                alert = "SystemdServiceFailed";
                expr = ''host_systemd_unit_failed{scope="system"} == 1 unless on(node, name) node_systemd_unit_state{state="failed"} == 1'';
                "for" = "5m";
                labels.severity = "warning";
                labels.source = "textfile"; # promtool lint: same name as the native rule needs a distinct label set
                annotations = {
                  summary = "Systemd unit failed on {{ $labels.node }}";
                  description = "Unit {{ $labels.name }} is in failed state on {{ $labels.node }}";
                };
              }
              {
                alert = "SystemdUserUnitFailed";
                expr = ''host_systemd_unit_failed{scope="user"} == 1'';
                "for" = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "User unit failed on {{ $labels.node }}";
                  description = "systemd --user unit {{ $labels.name }} ({{ $labels.user }}) is failed on {{ $labels.node }} — rootless docker stacks live here";
                };
              }
              {
                alert = "TailscaleDisconnected";
                expr = ''tailscale_backend_running{role="always_on"} == 0'';
                "for" = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Tailscale disconnected on {{ $labels.node }}";
                  description = "tailscaled on {{ $labels.node }} is not in Running state (Headscale unreachable or needs login)";
                };
              }
              {
                alert = "TailscaleDisconnected";
                expr = ''tailscale_backend_running{role="roaming"} == 0'';
                "for" = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "Tailscale disconnected on {{ $labels.node }}";
                  description = "tailscaled on {{ $labels.node }} is not in Running state (Headscale unreachable or needs login)";
                };
              }
              # The two peers every always-on node must see. nas-aku is not in the
              # list: the NAS sleeps, and HostDown covers it while it should be awake.
              {
                alert = "TailscaleKeyPeerOffline";
                expr = ''tailscale_peer_online{role="always_on", hostname=~"pfsense|vps-prod"} == 0'';
                "for" = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Tailscale peer {{ $labels.hostname }} offline as seen from {{ $labels.node }}";
                  description = "{{ $labels.node }} has not seen {{ $labels.hostname }} on the tailnet for 5 minutes";
                };
              }
              # "Not updated" = the active generation is old. install.sh and
              # autoSystemUpdate both create a generation, so both count.
              {
                alert = "SystemUpdateStale";
                expr = ''(time() - nixos_last_update_system_timestamp{role="always_on"}) > 14 * 86400'';
                "for" = "1h";
                labels.severity = "warning";
                labels.threshold = "14d";
                annotations = {
                  summary = "{{ $labels.node }} not updated for {{ $value | humanizeDuration }}";
                  description = "Active NixOS generation on {{ $labels.node }} is older than 14 days — run a deploy";
                };
              }
              {
                alert = "SystemUpdateStale";
                expr = ''(time() - nixos_last_update_system_timestamp{role="roaming"}) > 30 * 86400'';
                "for" = "1h";
                labels.severity = "warning";
                labels.threshold = "30d";
                annotations = {
                  summary = "{{ $labels.node }} not updated for {{ $value | humanizeDuration }}";
                  description = "Active NixOS generation on {{ $labels.node }} is older than 30 days — run a deploy";
                };
              }
              # ZFS health from the NAS textfile (the docker node-exporter has no zfs collector)
              {
                alert = "NASPoolDegraded";
                expr = ''nas_zfs_pool_healthy == 0'';
                "for" = "2m";
                labels.severity = "critical";
                annotations = {
                  summary = "ZFS pool {{ $labels.pool }} is not ONLINE";
                  description = "zpool list reports {{ $labels.pool }} degraded/faulted on {{ $labels.node }} — check zpool status before a disk is lost";
                };
              }
            ];
          }
          {
            # pfSense via SNMP (prometheus-snmp.nix): the only always-on box at home.
            # No pf* rules: BEGEMOT-PF-MIB (1.3.6.1.4.1.12325) is served by pfSense's
            # built-in bsnmpd, not by the NET-SNMP package we query — those OIDs come
            # back empty (verified 2026-09-11).
            name = "pfsense_alerts";
            rules = [
              {
                alert = "PfSenseUnreachable";
                expr = ''up{job="snmp_pfsense"} == 0'';
                "for" = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "pfSense not answering SNMP";
                  description = "The SNMP scrape of pfSense has failed for 3 minutes — router down, WireGuard tunnel down, or NET-SNMP stopped";
                };
              }
              # admin-up but oper-down: covers WAN, LAN trunk, tailscale0, tun_wg0 without naming them
              {
                alert = "PfSenseInterfaceDown";
                expr = ''ifOperStatus{job="snmp_pfsense"} == 2 and on(ifIndex) ifAdminStatus{job="snmp_pfsense"} == 1'';
                "for" = "3m";
                labels.severity = "critical";
                annotations = {
                  summary = "pfSense interface {{ $labels.ifDescr }} is down";
                  description = "{{ $labels.ifDescr }} is administratively up but has no link/operational status for 3 minutes";
                };
              }
              {
                alert = "PfSenseInterfaceErrors";
                expr = ''rate(ifInErrors{job="snmp_pfsense"}[5m]) + rate(ifOutErrors{job="snmp_pfsense"}[5m]) > 1'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "pfSense interface {{ $labels.ifDescr }} has errors";
                  description = "{{ $labels.ifDescr }} is seeing {{ $value | printf \"%.1f\" }} errors/s (cable, SFP or duplex problem)";
                };
              }
              {
                alert = "PfSenseDiskSpaceLow";
                expr = ''hrStorageUsed{job="snmp_pfsense", hrStorageDescr="/"} / hrStorageSize{job="snmp_pfsense", hrStorageDescr="/"} * 100 > 85'';
                "for" = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "pfSense root filesystem {{ $value | printf \"%.0f\" }}% full";
                  description = "Logs or pkg cache filling / on pfSense";
                };
              }
              {
                alert = "PfSenseCPUHigh";
                expr = ''avg(hrProcessorLoad{job="snmp_pfsense"}) > 85'';
                "for" = "15m";
                labels.severity = "warning";
                annotations = {
                  summary = "pfSense CPU {{ $value | printf \"%.0f\" }}% for 15 minutes";
                  description = "Sustained CPU load on the router (IDS/IPS, VPN crypto or a flood)";
                };
              }
              {
                alert = "PfSenseMemoryLow";
                expr = ''memAvailReal{job="snmp_pfsense"} / memTotalReal{job="snmp_pfsense"} * 100 < 10'';
                "for" = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "pfSense free memory under 10%";
                  description = "Only {{ $value | printf \"%.1f\" }}% RAM available on pfSense";
                };
              }
            ];
          }
        ];
      }))
    ];
  };

  # Install frser-sqlite-datasource plugin if not present (community plugin, not in nixpkgs)
  systemd.services.grafana.preStart = lib.mkAfter ''
    PLUGIN_DIR="${config.services.grafana.dataDir}/plugins/frser-sqlite-datasource"
    if [ ! -d "$PLUGIN_DIR" ]; then
      ${config.services.grafana.package}/bin/grafana cli --pluginsDir "${config.services.grafana.dataDir}/plugins" plugins install frser-sqlite-datasource || true
    fi
  '';

  # Allow grafana to read the Vaultkeeper finance SQLite database
  # Default systemd sandboxing (ProtectHome=yes) blocks access to /home/
  # ACLs (set via activation script) restrict grafana to only the finance-data dir
  systemd.services.grafana.serviceConfig.ProtectHome = lib.mkForce false;

  # Grant grafana traverse/read access to the Vaultkeeper finance SQLite database
  # Must run as root (activation script) since grafana user can't setfacl on other users' dirs
  system.activationScripts.grafana-finance-db-access = lib.stringAfter [ "users" ] ''
    FINANCE_DB_DIR="/home/${userSettings.username}/.openclaw/finance-data"
    if [ -d "$FINANCE_DB_DIR" ]; then
      ${pkgs.acl}/bin/setfacl -m u:grafana:x /home/${userSettings.username} || true
      ${pkgs.acl}/bin/setfacl -m u:grafana:x /home/${userSettings.username}/.openclaw || true
      ${pkgs.acl}/bin/setfacl -m u:grafana:rx "$FINANCE_DB_DIR" || true
    fi
  '';

  # Create textfile directory for custom metrics (auto-update status, backup status)
  # Mode 0775 allows group write access for user update scripts (wheel group)
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
  ];

  # Copy dashboard JSON files to /etc/grafana-dashboards for provisioning
  # Also provisions Prometheus htpasswd if basic auth is configured
  environment.etc = {
    # Prometheus HTTP Basic Auth (for nginx-local vhost)
    "nginx/auth/prometheus.htpasswd" = lib.mkIf ((systemSettings.prometheusBasicAuthHtpasswd or null) != null) {
      text = systemSettings.prometheusBasicAuthHtpasswd;
      mode = "0640";
      user = "root";
      group = config.services.nginx.group;
    };
    # Pocket ID OIDC client secret → read by Grafana at runtime via $__file{}
    # (keeps it out of the grafana.ini store path).
    "secrets/grafana-oauth-client-secret" = lib.mkIf oauthEnabled {
      text = systemSettings.grafanaOauthClientSecret or "";
      mode = "0440";
      user = "root";
      group = "grafana";
    };
    # Custom dashboards
    "grafana-dashboards/custom/wireguard.json".source = ./grafana-dashboards/custom/wireguard.json;
    "grafana-dashboards/custom/nas.json".source = ./grafana-dashboards/custom/nas.json;
    "grafana-dashboards/custom/pfsense.json".source = ./grafana-dashboards/custom/pfsense.json;
    "grafana-dashboards/custom/media-stack.json".source = ./grafana-dashboards/custom/media-stack.json;
    "grafana-dashboards/custom/infrastructure-status.json".source = ./grafana-dashboards/custom/infrastructure-status.json;
    "grafana-dashboards/custom/infrastructure-overview.json".source = ./grafana-dashboards/custom/infrastructure-overview.json;
    "grafana-dashboards/custom/public-infrastructure-overview.json".source = ./grafana-dashboards/custom/public-infrastructure-overview.json;
    "grafana-dashboards/custom/database-overview.json".source = ./grafana-dashboards/custom/database-overview.json;
    "grafana-dashboards/custom/database-deep-dive.json".source = ./grafana-dashboards/custom/database-deep-dive.json;
    "grafana-dashboards/custom/tailscale.json".source = ./grafana-dashboards/custom/tailscale.json;
    "grafana-dashboards/custom/finance-budget-cycle.json".source = ./grafana-dashboards/custom/finance-budget-cycle.json;
    "grafana-dashboards/custom/finance-budget-comparison.json".source = ./grafana-dashboards/custom/finance-budget-comparison.json;
    "grafana-dashboards/custom/finance-savings.json".source = ./grafana-dashboards/custom/finance-savings.json;
    "grafana-dashboards/custom/finance-investments.json".source = ./grafana-dashboards/custom/finance-investments.json;
    "grafana-dashboards/custom/finance-fire.json".source = ./grafana-dashboards/custom/finance-fire.json;
    # Community dashboards
    "grafana-dashboards/community/node-exporter-full.json".source = ./grafana-dashboards/community/node-exporter-full.json;
    "grafana-dashboards/community/docker-cadvisor.json".source = ./grafana-dashboards/community/docker-cadvisor.json;
    "grafana-dashboards/community/blackbox-exporter.json".source = ./grafana-dashboards/community/blackbox-exporter.json;
    "grafana-dashboards/community/docker-system-monitoring.json".source = ./grafana-dashboards/community/docker-system-monitoring.json;
  };

  # Nginx reverse proxy with SSL
  services.nginx = {
    enable = true;
    defaultHTTPListenPort = 80;
    defaultSSLListenPort = 443;

    # Security headers for all vhosts (SEC-AUDIT-001)
    appendHttpConfig = ''
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    '';

    virtualHosts = lib.mkMerge [
      # Grafana - public access via Cloudflare Tunnel (HTTP - TLS terminated by Cloudflare)
      {
        "grafana.${publicDomain}" = {
          listenAddresses = [ "127.0.0.1" ]; # Only cloudflared reaches this (SEC-AUDIT-001)
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
        };
      }

      # Local SSL vhosts (requires shared certs from Proxmox — not available on VPS)
      (lib.mkIf localSslEnable {
        # Grafana - main monitoring UI (local access with SSL)
        "${config.services.grafana.settings.server.domain}" = {
          onlySSL = true;
          sslCertificate = "/mnt/shared-certs/${wildcardLocal}.crt";
          sslCertificateKey = "/mnt/shared-certs/${wildcardLocal}.key";
          sslTrustedCertificate = "/mnt/shared-certs/${wildcardLocal}.crt";
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
            proxyWebsockets = true;
            recommendedProxySettings = true;
          };
        };

        # Prometheus - metrics API (protected with basic auth + IP whitelist)
        "prometheus.${wildcardLocal}" = {
          onlySSL = true;
          sslCertificate = "/mnt/shared-certs/${wildcardLocal}.crt";
          sslCertificateKey = "/mnt/shared-certs/${wildcardLocal}.key";
          sslTrustedCertificate = "/mnt/shared-certs/${wildcardLocal}.crt";
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
      })
    ];
  };
}
