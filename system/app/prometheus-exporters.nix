# Prometheus Exporters Module
# Enables Node Exporter and cAdvisor on monitored nodes for remote scraping
#
# Feature flags (from profile config):
#   - prometheusExporterEnable: Enable Node Exporter (system metrics)
#   - prometheusExporterCadvisorEnable: Enable cAdvisor (Docker container metrics)
#   - prometheusNodeExporterPort: Port for Node Exporter (default: 9100)
#   - prometheusCadvisorPort: Port for cAdvisor (default: 9092)

{ config, pkgs, lib, systemSettings, ... }:

let
  nodeExporterPort = systemSettings.prometheusNodeExporterPort or 9100;
  cadvisorPort = systemSettings.prometheusCadvisorPort or 9092;
in
{
  # Node Exporter - System metrics (CPU, memory, disk, network)
  services.prometheus.exporters.node = lib.mkIf (systemSettings.prometheusExporterEnable or false) {
    enable = true;
    port = nodeExporterPort;
    listenAddress = "0.0.0.0"; # Allow remote scraping from Prometheus server
    enabledCollectors = [
      "systemd"
      "processes"
      "textfile"  # Custom metrics from textfiles (e.g., auto-update status)
    ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile"
    ];
  };

  # Create textfile directory for custom metrics
  systemd.tmpfiles.rules = lib.mkIf (systemSettings.prometheusExporterEnable or false) [
    "d /var/lib/prometheus-node-exporter/textfile 0755 root root -"
  ];

  # cAdvisor - Docker container metrics
  services.cadvisor = lib.mkIf (systemSettings.prometheusExporterCadvisorEnable or false) {
    enable = true;
    port = cadvisorPort;
    listenAddress = "0.0.0.0"; # Allow remote scraping from Prometheus server
  };

  # Add cAdvisor package when enabled
  environment.systemPackages = lib.mkIf (systemSettings.prometheusExporterCadvisorEnable or false) [
    pkgs.cadvisor
  ];
}
