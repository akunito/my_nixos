# Graphite Exporter for TrueNAS Metrics
#
# TrueNAS has built-in Graphite reporting that can send metrics to this exporter.
# The exporter converts Graphite plaintext protocol to Prometheus metrics.
#
# Feature flags (from profile config):
#   - prometheusGraphiteEnable: Enable Graphite Exporter
#   - prometheusGraphitePort: Prometheus scrape port (default 9109)
#   - prometheusGraphiteInputPort: Graphite input port for TrueNAS (default 2003)
#
# TrueNAS Configuration:
#   1. Go to System > Reporting (TrueNAS SCALE) or System > Reporting > Graphite (CORE)
#   2. Enable Remote Graphite Server
#   3. Set Graphite Server: 192.168.8.85 (monitoring server IP)
#   4. Set Graphite Port: 2003 (or value of prometheusGraphiteInputPort)
#   5. Save and test
#
# Metrics exposed (examples from TrueNAS):
#   - servers_truenas_cpu_*: CPU usage metrics
#   - servers_truenas_memory_*: Memory usage
#   - servers_truenas_disktemp_*: Disk temperatures
#   - servers_truenas_df_*: Filesystem usage (including ZFS datasets)
#   - servers_truenas_interface_*: Network interface stats
#   - servers_truenas_zfs_*: ZFS pool and dataset metrics
#
# References:
# - https://mynixos.com/options/services.prometheus.exporters.graphite
# - https://github.com/prometheus/graphite_exporter

{ pkgs, lib, systemSettings, config, ... }:

let
  # Port for Prometheus to scrape metrics from
  webPort = systemSettings.prometheusGraphitePort or 9109;
  # Port for TrueNAS to send Graphite data to (must be different from webPort)
  graphiteInputPort = systemSettings.prometheusGraphiteInputPort or 2003;

  # Mapping configuration for TrueNAS Graphite metrics
  # Converts dot-separated Graphite names to labeled Prometheus metrics
  mappingConfig = {
    mappings = [
      # CPU metrics
      {
        match = "servers.*.cpu.*.percent.*";
        name = "truenas_cpu_percent";
        labels = {
          host = "\${1}";
          cpu = "\${2}";
          mode = "\${3}";
        };
      }
      # Memory metrics
      {
        match = "servers.*.memory.*";
        name = "truenas_memory_bytes";
        labels = {
          host = "\${1}";
          type = "\${2}";
        };
      }
      # Disk temperature
      {
        match = "servers.*.disktemp.*";
        name = "truenas_disk_temperature_celsius";
        labels = {
          host = "\${1}";
          disk = "\${2}";
        };
      }
      # Filesystem/ZFS dataset usage
      {
        match = "servers.*.df.*.df_complex.*";
        name = "truenas_filesystem_bytes";
        labels = {
          host = "\${1}";
          filesystem = "\${2}";
          type = "\${3}";
        };
      }
      # Network interface metrics
      {
        match = "servers.*.interface.*.if_octets.*";
        name = "truenas_interface_bytes";
        labels = {
          host = "\${1}";
          interface = "\${2}";
          direction = "\${3}";
        };
      }
      # ZFS ARC stats
      {
        match = "servers.*.zfs_arc.*";
        name = "truenas_zfs_arc";
        labels = {
          host = "\${1}";
          stat = "\${2}";
        };
      }
      # ZFS pool stats
      {
        match = "servers.*.zfs.*.gauge";
        name = "truenas_zfs_pool";
        labels = {
          host = "\${1}";
          pool = "\${2}";
        };
      }
      # CPU temperature (extract cpu core number as label)
      # Graphite path: servers.truenas.cputemp.temperatures.cpu0
      {
        match = "servers.*.cputemp.temperatures.*";
        name = "truenas_cputemp_celsius";
        labels = {
          host = "\${1}";
          cpu = "\${2}";
        };
      }
      # ZFS pool usage (custom script - truenas.zfspool.<pool>.<stat>)
      {
        match = "truenas.zfspool.*.*";
        name = "truenas_zfspool_\${2}";
        labels = {
          pool = "\${1}";
        };
      }
      # Catch-all for unmapped metrics (using single * wildcards)
      {
        match = "servers.*.*.*";
        name = "truenas_\${2}_\${3}";
        labels = {
          host = "\${1}";
        };
      }
      {
        match = "servers.*.*.*.*";
        name = "truenas_\${2}_\${3}_\${4}";
        labels = {
          host = "\${1}";
        };
      }
    ];
  };
in
lib.mkIf (systemSettings.prometheusGraphiteEnable or false) {
  # Graphite exporter service
  services.prometheus.exporters.graphite = {
    enable = true;
    port = webPort;                    # Prometheus scrape port (HTTP)
    listenAddress = "0.0.0.0";          # Must listen on all interfaces so TrueNAS can send via Tailscale/WireGuard
    graphitePort = graphiteInputPort;  # Graphite input from TrueNAS
    openFirewall = false;              # VPN interfaces (wg0, tailscale0) accept all traffic; no need to open publicly
    mappingSettings = mappingConfig;
  };

  # Graphite input port NOT opened publicly — TrueNAS connects via Tailscale/WireGuard,
  # and VPN interfaces (wg0, tailscale0) already accept all traffic in the NixOS firewall.

  # ZFS pool metrics exporter — SSHes to TrueNAS every 5 minutes and sends pool stats
  # to Graphite. TrueNAS SCALE doesn't export ZFS pool capacity via its built-in reporter.
  systemd.services.truenas-zfs-exporter = {
    description = "TrueNAS ZFS Pool Metrics Exporter";
    after = [ "network-online.target" "prometheus-graphite-exporter.service" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.openssh pkgs.netcat-gnu pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      User = "akunito";
      ExecStart = pkgs.writeShellScript "truenas-zfs-exporter" ''
        set -euo pipefail
        TRUENAS_HOST="truenas_admin@192.168.20.200"
        GRAPHITE_HOST="127.0.0.1"
        GRAPHITE_PORT="${toString graphiteInputPort}"
        TIMESTAMP=$(date +%s)

        # Get pool stats via zpool list (-H = no header, -p = parseable/bytes)
        # Columns: name, size, alloc, free, ckpoint, expandsz, frag%, cap%, dedup, health, altroot
        POOL_DATA=$(ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=no \
          "$TRUENAS_HOST" 'sudo zpool list -Hp' 2>/dev/null) || {
          echo "Failed to SSH to TrueNAS" >&2
          exit 1
        }

        # Parse and send each pool's metrics
        echo "$POOL_DATA" | while IFS=$'\t' read -r name size alloc free _ _ frag _ _ health _; do
          # Skip empty lines
          [ -z "$name" ] && continue

          # Determine healthy status (1=ONLINE, 0=anything else)
          healthy=0
          [ "$health" = "ONLINE" ] && healthy=1

          # Send metrics in Graphite plaintext format
          {
            echo "truenas.zfspool.$name.size $size $TIMESTAMP"
            echo "truenas.zfspool.$name.allocated $alloc $TIMESTAMP"
            echo "truenas.zfspool.$name.free $free $TIMESTAMP"
            echo "truenas.zfspool.$name.fragmentation $frag $TIMESTAMP"
            echo "truenas.zfspool.$name.healthy $healthy $TIMESTAMP"
          } | nc -w 5 "$GRAPHITE_HOST" "$GRAPHITE_PORT"
        done
      '';
    };
  };

  systemd.timers.truenas-zfs-exporter = {
    description = "TrueNAS ZFS Pool Metrics Exporter Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      RandomizedDelaySec = "30s";
    };
  };

  # Prometheus scrape config for graphite exporter
  services.prometheus.scrapeConfigs = [
    {
      job_name = "truenas_graphite";
      static_configs = [{
        targets = [ "127.0.0.1:${toString webPort}" ];
        labels = {
          instance = "truenas";
        };
      }];
      # Longer scrape interval since Graphite pushes data
      scrape_interval = "30s";
    }
  ];

  # Alert rules for TrueNAS/ZFS storage
  services.prometheus.ruleFiles = [
    (pkgs.writeText "truenas-alerts.yml" (builtins.toJSON {
      groups = [
        {
          name = "truenas_alerts";
          rules = [
            # Pool capacity warning (>80%)
            # Uses custom truenas-zfs-exporter.sh metrics
            {
              alert = "TrueNASPoolCapacityWarning";
              expr = ''
                (
                  truenas_zfspool_allocated
                  /
                  truenas_zfspool_size
                ) * 100 > 80
              '';
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "TrueNAS pool {{ $labels.pool }} capacity warning";
                description = "Pool {{ $labels.pool }} is at {{ $value | printf \"%.1f\" }}% capacity";
              };
            }
            # Pool capacity critical (>90%)
            {
              alert = "TrueNASPoolCapacityCritical";
              expr = ''
                (
                  truenas_zfspool_allocated
                  /
                  truenas_zfspool_size
                ) * 100 > 90
              '';
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "TrueNAS pool {{ $labels.pool }} capacity critical";
                description = "Pool {{ $labels.pool }} is at {{ $value | printf \"%.1f\" }}% capacity - immediate attention required";
              };
            }
            # Pool unhealthy (ZFS pool status not ONLINE)
            {
              alert = "TrueNASPoolUnhealthy";
              expr = ''truenas_zfspool_healthy == 0'';
              "for" = "2m";
              labels.severity = "critical";
              annotations = {
                summary = "TrueNAS pool {{ $labels.pool }} unhealthy";
                description = "Pool {{ $labels.pool }} is reporting unhealthy status - check pool status immediately";
              };
            }
            # Disk temperature warning (>45°C)
            {
              alert = "TrueNASDiskTempWarning";
              expr = ''truenas_disk_temperature_celsius > 45'';
              "for" = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "TrueNAS disk {{ $labels.disk }} temperature warning";
                description = "Disk {{ $labels.disk }} temperature is {{ $value }}°C";
              };
            }
            # Disk temperature critical (>55°C)
            {
              alert = "TrueNASDiskTempCritical";
              expr = ''truenas_disk_temperature_celsius > 55'';
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "TrueNAS disk {{ $labels.disk }} temperature critical";
                description = "Disk {{ $labels.disk }} temperature is {{ $value }}°C - risk of hardware damage";
              };
            }
            # TrueNAS not reporting (no metrics received for 5+ minutes)
            {
              alert = "TrueNASNotReporting";
              expr = ''absent(truenas_cpu_percent) or (time() - max(timestamp(truenas_cpu_percent)) > 300)'';
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "TrueNAS not reporting metrics";
                description = "No Graphite metrics received from TrueNAS for more than 5 minutes";
              };
            }
            # High memory usage (>90%)
            {
              alert = "TrueNASMemoryHigh";
              expr = ''
                (
                  truenas_memory_bytes{type="used"}
                  /
                  (truenas_memory_bytes{type="used"} + truenas_memory_bytes{type="free"} + truenas_memory_bytes{type="cached"})
                ) * 100 > 90
              '';
              "for" = "10m";
              labels.severity = "warning";
              annotations = {
                summary = "TrueNAS memory usage high";
                description = "TrueNAS memory usage is at {{ $value | printf \"%.1f\" }}%";
              };
            }
            # ZFS replication backup alerts removed — hddpool eliminated, no more cross-pool replication
          ];
        }
      ];
    }))
  ];
}
