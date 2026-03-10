# Prometheus Workstation Exporter Module
# Lightweight node exporter for workstations (DESK, laptops)
# Only exposes: textfile (update/backup metrics), filesystem, diskstats
#
# Feature flag: prometheusWorkstationExporterEnable (default: false)
# Guard: never activates if full prometheusExporterEnable is already true
#
# Port: 9100 (standard node exporter port)

{ config, pkgs, lib, systemSettings, ... }:

lib.mkIf
  ((systemSettings.prometheusWorkstationExporterEnable or false)
   && !(systemSettings.prometheusExporterEnable or false))
{
  # Lightweight Node Exporter — only textfile, filesystem, diskstats collectors
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = "0.0.0.0";
    enabledCollectors = [
      "textfile"
      "filesystem"
      "diskstats"
    ];
    extraFlags = [
      "--collector.disable-defaults"
      "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile"
    ];
  };

  # Create textfile directory for custom metrics
  # Mode 0775 allows group write access for user update scripts (wheel group)
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
  ];

  # NixOS update timestamp exporter — writes last system/user rebuild time to textfile
  # Self-contained copy from prometheus-exporters.nix (modules stay independent)
  systemd.services.nixos-update-metrics = {
    description = "Export NixOS last update timestamps for Prometheus";
    after = [ "network.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nixos-update-metrics" ''
        set -euo pipefail
        TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
        HOSTNAME=$(cat /proc/sys/kernel/hostname)
        OUTFILE="$TEXTFILE_DIR/nixos_updates.prom"

        # System rebuild timestamp (current NixOS generation)
        SYSTEM_TS=$(stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || echo 0)

        # Home Manager rebuild timestamp (current user generation)
        # Check both legacy (/nix/var/nix/profiles/per-user/*/home-manager)
        # and modern (~/.local/state/nix/profiles/home-manager) locations
        USER_TS=0
        for hm_profile in /nix/var/nix/profiles/per-user/*/home-manager /home/*/.local/state/nix/profiles/home-manager; do
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

  systemd.timers.nixos-update-metrics = {
    description = "Export NixOS update timestamps periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "15min";
    };
  };
}
