# Graphite Exporter for TrueNAS Metrics
#
# TrueNAS has built-in Graphite reporting that can send metrics to this exporter.
# The exporter converts Graphite plaintext protocol to Prometheus metrics.
#
# Feature flags (from profile config):
#   - prometheusGraphiteEnable: Enable Graphite Exporter
#   - prometheusGraphitePort: Port for Graphite input (default 9109)
#
# TrueNAS Configuration:
#   1. Go to System > Reporting (TrueNAS SCALE) or System > Reporting > Graphite (CORE)
#   2. Enable Remote Graphite Server
#   3. Set Graphite Server: 192.168.8.85 (monitoring server IP)
#   4. Set Graph Age and Port settings as needed
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
  graphitePort = systemSettings.prometheusGraphitePort or 9109;

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
    port = graphitePort;          # Prometheus scrape port
    openFirewall = true;          # Allow Graphite input from TrueNAS
    mappingSettings = mappingConfig;
    # Note: strict-match defaults to false, no extra flags needed
  };

  # Prometheus scrape config for graphite exporter
  services.prometheus.scrapeConfigs = [
    {
      job_name = "truenas_graphite";
      static_configs = [{
        targets = [ "127.0.0.1:${toString graphitePort}" ];
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
            # Filesystem capacity warning (>80%)
            # Uses df_complex metrics from TrueNAS collectd
            {
              alert = "TrueNASFilesystemCapacityWarning";
              expr = ''
                (
                  sum by (filesystem) (truenas_filesystem_bytes{type="used"})
                  /
                  (sum by (filesystem) (truenas_filesystem_bytes{type="used"}) + sum by (filesystem) (truenas_filesystem_bytes{type="free"}))
                ) * 100 > 80
              '';
              "for" = "5m";
              labels.severity = "warning";
              annotations = {
                summary = "TrueNAS filesystem {{ $labels.filesystem }} capacity warning";
                description = "Filesystem {{ $labels.filesystem }} is at {{ $value | printf \"%.1f\" }}% capacity";
              };
            }
            # Filesystem capacity critical (>90%)
            {
              alert = "TrueNASFilesystemCapacityCritical";
              expr = ''
                (
                  sum by (filesystem) (truenas_filesystem_bytes{type="used"})
                  /
                  (sum by (filesystem) (truenas_filesystem_bytes{type="used"}) + sum by (filesystem) (truenas_filesystem_bytes{type="free"}))
                ) * 100 > 90
              '';
              "for" = "5m";
              labels.severity = "critical";
              annotations = {
                summary = "TrueNAS filesystem {{ $labels.filesystem }} capacity critical";
                description = "Filesystem {{ $labels.filesystem }} is at {{ $value | printf \"%.1f\" }}% capacity - immediate attention required";
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
          ];
        }
      ];
    }))
  ];
}
