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
    listenAddress = if systemSettings.prometheusExporterLocalOnly or false then "127.0.0.1" else "0.0.0.0";
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
  # Mode 0775 allows group write access for user update scripts (wheel group)
  systemd.tmpfiles.rules = lib.mkIf (systemSettings.prometheusExporterEnable or false) [
    "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
  ];

  # NixOS update timestamp exporter — writes last system/user rebuild time to textfile
  # Reads modification time of the current NixOS system profile and HM generation
  systemd.services.nixos-update-metrics = lib.mkIf (systemSettings.prometheusExporterEnable or false) {
    description = "Export NixOS last update timestamps for Prometheus";
    after = [ "network.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nixos-update-metrics" ''
        set -euo pipefail
        TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
        HOSTNAME=$(hostname)
        OUTFILE="$TEXTFILE_DIR/nixos_updates.prom"

        # System rebuild timestamp (current NixOS generation)
        SYSTEM_TS=$(stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || echo 0)

        # Home Manager rebuild timestamp (current user generation)
        # Check common HM profile locations
        USER_TS=0
        for hm_profile in /nix/var/nix/profiles/per-user/*/home-manager; do
          if [ -e "$hm_profile" ]; then
            ts=$(stat -c %Y "$hm_profile" 2>/dev/null || echo 0)
            [ "$ts" -gt "$USER_TS" ] && USER_TS=$ts
          fi
        done

        cat > "$OUTFILE.tmp" <<METRICS
# HELP nixos_last_update_system_timestamp Unix timestamp of last NixOS system rebuild
# TYPE nixos_last_update_system_timestamp gauge
nixos_last_update_system_timestamp{hostname="$HOSTNAME"} $SYSTEM_TS
# HELP nixos_last_update_user_timestamp Unix timestamp of last Home Manager rebuild
# TYPE nixos_last_update_user_timestamp gauge
nixos_last_update_user_timestamp{hostname="$HOSTNAME"} $USER_TS
METRICS
        mv "$OUTFILE.tmp" "$OUTFILE"
      '';
    };
  };

  systemd.timers.nixos-update-metrics = lib.mkIf (systemSettings.prometheusExporterEnable or false) {
    description = "Export NixOS update timestamps periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "15min";
    };
  };

  # cAdvisor - Docker container metrics
  services.cadvisor = lib.mkIf (systemSettings.prometheusExporterCadvisorEnable or false) {
    enable = true;
    port = cadvisorPort;
    listenAddress = if systemSettings.prometheusExporterLocalOnly or false then "127.0.0.1" else "0.0.0.0";
  };

  # Add cAdvisor package when enabled
  environment.systemPackages = lib.mkIf (systemSettings.prometheusExporterCadvisorEnable or false) [
    pkgs.cadvisor
  ];
}
