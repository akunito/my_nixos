# pfSense Backup Monitoring
#
# Monitors pfSense backup files on Proxmox NFS storage and exposes metrics via textfile collector.
# This runs on the monitoring server and checks backup files via SSH to Proxmox.
#
# Metrics exposed:
#   pfsense_backup_last_success - Unix timestamp of last successful backup
#   pfsense_backup_age_seconds - Seconds since last backup
#   pfsense_backup_count - Number of backup files retained
#   pfsense_backup_size_bytes - Size of latest backup in bytes
#
# Feature flag: prometheusPfsenseBackupEnable

{ config, pkgs, lib, systemSettings, ... }:

let
  proxmoxHost = systemSettings.prometheusPfsenseBackupProxmoxHost or "192.168.8.82";
  backupPath = systemSettings.prometheusPfsenseBackupPath or "/mnt/pve/proxmox_backups/pfsense";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  # Script to check pfSense backup status via SSH to Proxmox
  pfsenseBackupScript = pkgs.writeShellScript "pfsense-backup-metrics" ''
    #!/bin/bash
    set -euo pipefail

    PROXMOX_HOST="${proxmoxHost}"
    BACKUP_PATH="${backupPath}"
    TEXTFILE="${textfileDir}/pfsense_backup.prom"
    TEMP_FILE=$(mktemp)

    # Check backup files via SSH
    BACKUP_INFO=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=10 -o BatchMode=yes \
      "root@$PROXMOX_HOST" \
      "ls -lt --time-style=+%s ${backupPath}/pfsense-full-backup-*.tar.gz 2>/dev/null | head -1" \
      2>/dev/null || echo "")

    if [ -z "$BACKUP_INFO" ]; then
      # No backups found
      cat > "$TEMP_FILE" << 'METRICS'
# HELP pfsense_backup_last_success Unix timestamp of last successful backup
# TYPE pfsense_backup_last_success gauge
pfsense_backup_last_success 0
# HELP pfsense_backup_status 1 if backup exists, 0 if not
# TYPE pfsense_backup_status gauge
pfsense_backup_status 0
# HELP pfsense_backup_count Number of backup files retained
# TYPE pfsense_backup_count gauge
pfsense_backup_count 0
METRICS
    else
      # Parse backup info: -rwxrwxrwx 1 nobody root 2644361 1738963850 pfsense-full-backup-...
      MTIME=$(echo "$BACKUP_INFO" | awk '{print $6}')
      SIZE=$(echo "$BACKUP_INFO" | awk '{print $5}')

      # Get backup count
      COUNT=$(${pkgs.openssh}/bin/ssh -o ConnectTimeout=10 -o BatchMode=yes \
        "root@$PROXMOX_HOST" \
        "ls -1 ${backupPath}/pfsense-full-backup-*.tar.gz 2>/dev/null | wc -l" \
        2>/dev/null || echo "0")

      NOW=$(date +%s)
      AGE=$((NOW - MTIME))

      cat > "$TEMP_FILE" << METRICS
# HELP pfsense_backup_last_success Unix timestamp of last successful backup
# TYPE pfsense_backup_last_success gauge
pfsense_backup_last_success $MTIME
# HELP pfsense_backup_status 1 if backup exists, 0 if not
# TYPE pfsense_backup_status gauge
pfsense_backup_status 1
# HELP pfsense_backup_age_seconds Seconds since last backup
# TYPE pfsense_backup_age_seconds gauge
pfsense_backup_age_seconds $AGE
# HELP pfsense_backup_count Number of backup files retained
# TYPE pfsense_backup_count gauge
pfsense_backup_count $COUNT
# HELP pfsense_backup_size_bytes Size of latest backup in bytes
# TYPE pfsense_backup_size_bytes gauge
pfsense_backup_size_bytes $SIZE
METRICS
    fi

    # Atomically move to final location
    mv "$TEMP_FILE" "$TEXTFILE"
    chmod 644 "$TEXTFILE"

    echo "pfSense backup metrics written to $TEXTFILE"
  '';

in
{
  config = lib.mkIf (systemSettings.prometheusPfsenseBackupEnable or false) {
    # Systemd service to collect backup metrics
    systemd.services.prometheus-pfsense-backup = {
      description = "pfSense Backup Metrics Collector";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pfsenseBackupScript}";
        User = "root";
        Restart = "on-failure";
        RestartSec = "60s";
      };

      preStart = ''
        mkdir -p ${textfileDir}
      '';
    };

    # Timer to run hourly
    systemd.timers.prometheus-pfsense-backup = {
      description = "pfSense Backup Metrics Collection Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1h";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
  };
}
