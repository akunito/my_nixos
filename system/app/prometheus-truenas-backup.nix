# TrueNAS ZFS Replication Backup Monitoring
#
# Monitors ZFS replication tasks (ssdpool → hddpool/ssd_data_backups) by
# SSHing to TrueNAS and checking the age of the newest autoreplica-* snapshot
# on each destination dataset.
#
# Metrics exposed (via textfile collector):
#   truenas_backup_age_seconds{dataset} - Seconds since last replication snapshot
#   truenas_backup_last_success{dataset} - Unix timestamp of last snapshot
#   truenas_backup_status{dataset} - 1 = snapshot found, 0 = no snapshot found
#
# Feature flags (from profile config):
#   - prometheusTruenasBackupEnable: Enable TrueNAS backup monitoring
#   - prometheusTruenasBackupHost: TrueNAS IP (default 192.168.20.200)
#   - prometheusTruenasBackupUser: SSH user (default truenas_admin)
#
# Prerequisites:
#   Root on LXC_monitoring must have SSH key access to truenas_admin@<host>
#   ssh-copy-id -i /root/.ssh/id_ed25519.pub truenas_admin@192.168.20.200

{ config, pkgs, lib, systemSettings, ... }:

let
  truenasHost = systemSettings.prometheusTruenasBackupHost or "192.168.20.200";
  truenasUser = systemSettings.prometheusTruenasBackupUser or "truenas_admin";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  # Datasets to monitor (destination of daily replication tasks)
  datasets = [
    "hddpool/ssd_data_backups/library"
    "hddpool/ssd_data_backups/emulators"
    "hddpool/ssd_data_backups/services"
  ];

  datasetsStr = lib.concatStringsSep " " datasets;

  truenasBackupScript = pkgs.writeShellScript "truenas-backup-metrics" ''
    #!/bin/bash
    set -euo pipefail

    TRUENAS_HOST="${truenasHost}"
    TRUENAS_USER="${truenasUser}"
    TEXTFILE="${textfileDir}/truenas_backup.prom"
    TEMP_FILE=$(mktemp)
    NOW=$(date +%s)

    SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"

    # Write metric headers
    cat > "$TEMP_FILE" << 'HEADER'
# HELP truenas_backup_age_seconds Seconds since last ZFS replication snapshot
# TYPE truenas_backup_age_seconds gauge
# HELP truenas_backup_last_success Unix timestamp of last replication snapshot
# TYPE truenas_backup_last_success gauge
# HELP truenas_backup_status Whether a replication snapshot exists (1=ok, 0=no snapshot)
# TYPE truenas_backup_status gauge
HEADER

    DATASETS="${datasetsStr}"

    for dataset in $DATASETS; do
      # Get the short name for the label (last path component)
      short_name=$(${pkgs.coreutils}/bin/basename "$dataset")

      # Query TrueNAS for the newest autoreplica-* snapshot on this dataset
      # zfs list -t snapshot -o name,creation -s creation -r <dataset> | grep autoreplica | tail -1
      SNAPSHOT_INFO=$(${pkgs.openssh}/bin/ssh $SSH_OPTS "$TRUENAS_USER@$TRUENAS_HOST" \
        "sudo zfs list -t snapshot -o name,creation -Hp -s creation -r $dataset 2>/dev/null | grep autoreplica | tail -1" 2>/dev/null || echo "")

      if [ -n "$SNAPSHOT_INFO" ]; then
        # Extract creation timestamp (second column, -Hp gives unix timestamp)
        SNAP_TIME=$(echo "$SNAPSHOT_INFO" | ${pkgs.gawk}/bin/awk '{print $2}')

        if [ -n "$SNAP_TIME" ] && [ "$SNAP_TIME" -gt 0 ] 2>/dev/null; then
          AGE=$((NOW - SNAP_TIME))
          echo "truenas_backup_age_seconds{dataset=\"$short_name\"} $AGE" >> "$TEMP_FILE"
          echo "truenas_backup_last_success{dataset=\"$short_name\"} $SNAP_TIME" >> "$TEMP_FILE"
          echo "truenas_backup_status{dataset=\"$short_name\"} 1" >> "$TEMP_FILE"
        else
          # Snapshot found but couldn't parse timestamp
          echo "truenas_backup_status{dataset=\"$short_name\"} 0" >> "$TEMP_FILE"
        fi
      else
        # No autoreplica snapshot found
        echo "truenas_backup_status{dataset=\"$short_name\"} 0" >> "$TEMP_FILE"
      fi
    done

    # Atomically move to final location
    mv "$TEMP_FILE" "$TEXTFILE"
    chmod 644 "$TEXTFILE"

    echo "TrueNAS backup metrics written to $TEXTFILE"
  '';

in
{
  config = lib.mkIf (systemSettings.prometheusTruenasBackupEnable or false) {
    # Systemd service to collect backup metrics
    systemd.services.prometheus-truenas-backup = {
      description = "TrueNAS ZFS Replication Backup Metrics Collector";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${truenasBackupScript}";
        User = "root";
        Restart = "on-failure";
        RestartSec = "60s";
      };

      preStart = ''
        mkdir -p ${textfileDir}
      '';
    };

    # Timer to run every 30 minutes
    systemd.timers.prometheus-truenas-backup = {
      description = "TrueNAS ZFS Replication Backup Metrics Collection Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "30min";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
  };
}
