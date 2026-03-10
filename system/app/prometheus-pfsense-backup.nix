# pfSense Config Backup + Sync + Monitoring
#
# 1. SSH to pfSense (admin@192.168.8.1 via WireGuard), pull /conf/config.xml
# 2. Save as compressed .xml.gz in local backup dir on VPS
# 3. Rotate old backups (configurable retention days)
# 4. Rsync backup dir to TrueNAS (truenas_admin@192.168.20.200)
# 5. Write textfile metrics for Prometheus
#
# Metrics exposed:
#   pfsense_backup_last_success - Unix timestamp of last successful backup
#   pfsense_backup_age_seconds - Seconds since last backup
#   pfsense_backup_count - Number of backup files retained
#   pfsense_backup_status - 1 if backup succeeded, 0 if failed
#
# Feature flag: prometheusPfsenseBackupEnable
# Runs as: User = "akunito" (has SSH keys to pfSense and TrueNAS)
# Timer: daily at 14:00 (TrueNAS awake window 11:00-23:00)

{ config, pkgs, lib, systemSettings, ... }:

let
  localDir = systemSettings.prometheusPfsenseBackupLocalDir or "/var/lib/pfsense-backups";
  truenasDir = systemSettings.prometheusPfsenseBackupTruenasDir or "/mnt/ssdpool/pfsense-backups";
  keepDays = toString (systemSettings.prometheusPfsenseBackupKeepDays or 30);
  truenasHost = systemSettings.prometheusTruenasBackupHost or "192.168.20.200";
  truenasUser = systemSettings.prometheusTruenasBackupUser or "truenas_admin";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  pfsenseBackupScript = pkgs.writeShellScript "pfsense-backup" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.openssh pkgs.rsync pkgs.gzip pkgs.findutils ]}:$PATH"

    BACKUP_DIR="${localDir}"
    TEXTFILE="${textfileDir}/pfsense_backup.prom"
    TEMP_FILE=$(mktemp)
    NOW=$(date +%s)
    DATE=$(date +%Y%m%d-%H%M%S)
    SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new"
    BACKUP_OK=0
    RSYNC_OK=0

    mkdir -p "$BACKUP_DIR"

    # --- Step 1: Pull config.xml from pfSense ---
    BACKUP_FILE="$BACKUP_DIR/pfsense-config-$DATE.xml.gz"

    if ssh $SSH_OPTS admin@192.168.8.1 "cat /conf/config.xml" 2>/dev/null | gzip > "$BACKUP_FILE.tmp"; then
      # Verify the file is non-empty
      if [ -s "$BACKUP_FILE.tmp" ]; then
        mv "$BACKUP_FILE.tmp" "$BACKUP_FILE"
        BACKUP_OK=1
        echo "pfSense config backup saved to $BACKUP_FILE"
      else
        rm -f "$BACKUP_FILE.tmp"
        echo "ERROR: Downloaded config.xml is empty" >&2
      fi
    else
      rm -f "$BACKUP_FILE.tmp"
      echo "ERROR: Failed to SSH to pfSense or pull config.xml" >&2
    fi

    # --- Step 2: Rotate old backups ---
    if [ "$BACKUP_OK" -eq 1 ]; then
      find "$BACKUP_DIR" -name "pfsense-config-*.xml.gz" -mtime +${keepDays} -delete 2>/dev/null || true
    fi

    # --- Step 3: Rsync to TrueNAS (non-fatal) ---
    if [ "$BACKUP_OK" -eq 1 ]; then
      if rsync -az --timeout=30 -e "ssh $SSH_OPTS" \
        "$BACKUP_DIR/" "${truenasUser}@${truenasHost}:${truenasDir}/" 2>/dev/null; then
        RSYNC_OK=1
        echo "Rsync to TrueNAS succeeded"
      else
        echo "WARNING: Rsync to TrueNAS failed (non-fatal)" >&2
      fi
    fi

    # --- Step 4: Write metrics ---
    if [ "$BACKUP_OK" -eq 1 ]; then
      # Find newest backup file timestamp
      NEWEST=$(find "$BACKUP_DIR" -name "pfsense-config-*.xml.gz" -printf '%T@\n' | sort -n | tail -1)
      NEWEST_INT=''${NEWEST%.*}
      AGE=$((NOW - NEWEST_INT))
      COUNT=$(find "$BACKUP_DIR" -name "pfsense-config-*.xml.gz" | wc -l)

      cat > "$TEMP_FILE" << METRICS
# HELP pfsense_backup_last_success Unix timestamp of last successful backup
# TYPE pfsense_backup_last_success gauge
pfsense_backup_last_success $NEWEST_INT
# HELP pfsense_backup_age_seconds Seconds since last backup
# TYPE pfsense_backup_age_seconds gauge
pfsense_backup_age_seconds $AGE
# HELP pfsense_backup_count Number of backup files retained
# TYPE pfsense_backup_count gauge
pfsense_backup_count $COUNT
# HELP pfsense_backup_status 1 if backup succeeded, 0 if failed
# TYPE pfsense_backup_status gauge
pfsense_backup_status 1
# HELP pfsense_backup_rsync_status 1 if rsync to TrueNAS succeeded, 0 if failed
# TYPE pfsense_backup_rsync_status gauge
pfsense_backup_rsync_status $RSYNC_OK
METRICS
    else
      cat > "$TEMP_FILE" << 'METRICS'
# HELP pfsense_backup_last_success Unix timestamp of last successful backup
# TYPE pfsense_backup_last_success gauge
pfsense_backup_last_success 0
# HELP pfsense_backup_age_seconds Seconds since last backup
# TYPE pfsense_backup_age_seconds gauge
pfsense_backup_age_seconds 0
# HELP pfsense_backup_count Number of backup files retained
# TYPE pfsense_backup_count gauge
pfsense_backup_count 0
# HELP pfsense_backup_status 1 if backup succeeded, 0 if failed
# TYPE pfsense_backup_status gauge
pfsense_backup_status 0
# HELP pfsense_backup_rsync_status 1 if rsync to TrueNAS succeeded, 0 if failed
# TYPE pfsense_backup_rsync_status gauge
pfsense_backup_rsync_status 0
METRICS
    fi

    mv "$TEMP_FILE" "$TEXTFILE"
    chmod 644 "$TEXTFILE"
    echo "pfSense backup metrics written to $TEXTFILE"
  '';

in
{
  config = lib.mkIf (systemSettings.prometheusPfsenseBackupEnable or false) {
    # Ensure backup directory exists
    systemd.tmpfiles.rules = [
      "d ${localDir} 0755 akunito users -"
    ];

    # Systemd service
    systemd.services.prometheus-pfsense-backup = {
      description = "pfSense Config Backup + Sync + Metrics";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pfsenseBackupScript}";
        User = "akunito";
      };

      preStart = ''
        mkdir -p ${textfileDir}
      '';
    };

    # Timer: daily at 14:00
    systemd.timers.prometheus-pfsense-backup = {
      description = "pfSense Backup Timer (daily 14:00)";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "*-*-* 14:00:00";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
  };
}
