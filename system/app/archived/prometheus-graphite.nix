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

  # Graphite input port NOT opened publicly — Graphite producers connect via
  # Tailscale/WireGuard, and VPN interfaces (wg0, tailscale0) already accept
  # all traffic in the NixOS firewall.
  #
  # NOTE: The legacy SSH-pull truenas-zfs-exporter + its scrape job + its
  # truenas_alerts rule group have been removed (AINF cleanup). ZFS pool
  # metrics are now produced on the NAS itself by `nas-zfs-pool-metrics`
  # (`system/app/nas-services.nix`), surfaced via the textfile collector,
  # and scraped by the `nas_node` job (`grafana.nix`). Alerts live in the
  # `nas_alerts` rule group in `grafana.nix`. This file is kept as a
  # Graphite-exporter shell only — useful if a future non-TrueNAS Graphite
  # producer ever needs it.
}
