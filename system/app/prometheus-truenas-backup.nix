# TrueNAS Restic Backup Monitoring
#
# Monitors restic backup repositories on TrueNAS by checking the newest file
# timestamp in each repo's snapshots/ directory (no restic password needed).
#
# Monitored repos:
#   vps_databases  — /mnt/extpool/vps-backups/databases.restic
#   vps_services   — /mnt/extpool/vps-backups/services.restic
#   vps_nextcloud  — /mnt/extpool/vps-backups/nextcloud.restic
#   desk_home      — /mnt/ssdpool/workstation_backups/nixosaku/home.restic
#   x13_home       — /mnt/ssdpool/workstation_backups/nixosx13aku/home.restic
#
# Metrics exposed (via textfile collector):
#   truenas_backup_age_seconds{dataset} - Seconds since newest snapshot file
#   truenas_backup_last_success{dataset} - Unix timestamp of newest snapshot file
#   truenas_backup_status{dataset} - 1 = files found, 0 = no files or unreachable
#   backup_repo_size_bytes{dataset,direction} - Size of backup repository in bytes
#
# Feature flag: prometheusTruenasBackupEnable
# Runs as: User = "akunito" (has SSH key to truenas_admin)
# Timer: daily at 13:00 (before pfSense backup at 14:00)

{ config, pkgs, lib, systemSettings, ... }:

let
  truenasHost = systemSettings.prometheusTruenasBackupHost or "192.168.20.200";
  truenasUser = systemSettings.prometheusTruenasBackupUser or "truenas_admin";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  # Restic repos to monitor: { label, path, direction }
  repos = [
    { label = "vps_databases"; path = "/mnt/extpool/vps-backups/databases.restic"; direction = "vps_to_truenas"; }
    { label = "vps_services";  path = "/mnt/extpool/vps-backups/services.restic"; direction = "vps_to_truenas"; }
    { label = "vps_nextcloud"; path = "/mnt/extpool/vps-backups/nextcloud.restic"; direction = "vps_to_truenas"; }
    { label = "desk_home";     path = "/mnt/ssdpool/workstation_backups/nixosaku/home.restic"; direction = "workstation_to_truenas"; }
    { label = "x13_home";      path = "/mnt/ssdpool/workstation_backups/nixosx13aku/home.restic"; direction = "workstation_to_truenas"; }
  ];

  # Build shell-friendly repo list: "label|path|direction label|path|direction ..."
  repoEntries = lib.concatMapStringsSep " " (r: "${r.label}|${r.path}|${r.direction}") repos;

  truenasBackupScript = pkgs.writeShellScript "truenas-backup-metrics" ''
    set -uo pipefail
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.openssh pkgs.findutils pkgs.gawk ]}:$PATH"

    TRUENAS_HOST="${truenasHost}"
    TRUENAS_USER="${truenasUser}"
    TEXTFILE="${textfileDir}/truenas_backup.prom"
    TEMP_FILE=$(mktemp)
    NOW=$(date +%s)
    SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new"

    # Write metric headers
    cat > "$TEMP_FILE" << 'HEADER'
# HELP truenas_backup_age_seconds Seconds since newest restic snapshot file
# TYPE truenas_backup_age_seconds gauge
# HELP truenas_backup_last_success Unix timestamp of newest restic snapshot file
# TYPE truenas_backup_last_success gauge
# HELP truenas_backup_status Whether restic repo has snapshot files (1=ok, 0=missing)
# TYPE truenas_backup_status gauge
# HELP backup_repo_size_bytes Size of backup repository in bytes
# TYPE backup_repo_size_bytes gauge
HEADER

    REPOS="${repoEntries}"

    for entry in $REPOS; do
      LABEL="$(echo "$entry" | cut -d'|' -f1)"
      REPO_PATH="$(echo "$entry" | cut -d'|' -f2)"
      DIRECTION="$(echo "$entry" | cut -d'|' -f3)"

      # Get newest snapshot timestamp + repo size in one SSH call
      RESULT=$(ssh $SSH_OPTS "$TRUENAS_USER@$TRUENAS_HOST" \
        "echo NEWEST=\$(sudo find $REPO_PATH/snapshots/ -maxdepth 1 -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1); echo SIZE=\$(sudo du -sb $REPO_PATH 2>/dev/null | cut -f1)" \
        2>/dev/null || echo "")

      NEWEST_TS=$(echo "$RESULT" | grep '^NEWEST=' | cut -d= -f2)
      REPO_SIZE=$(echo "$RESULT" | grep '^SIZE=' | cut -d= -f2)

      if [ -n "$NEWEST_TS" ] && [ "''${NEWEST_TS%.*}" -gt 0 ] 2>/dev/null; then
        NEWEST_INT="''${NEWEST_TS%.*}"
        AGE=$((NOW - NEWEST_INT))
        echo "truenas_backup_age_seconds{dataset=\"$LABEL\"} $AGE" >> "$TEMP_FILE"
        echo "truenas_backup_last_success{dataset=\"$LABEL\"} $NEWEST_INT" >> "$TEMP_FILE"
        echo "truenas_backup_status{dataset=\"$LABEL\"} 1" >> "$TEMP_FILE"
      else
        echo "truenas_backup_status{dataset=\"$LABEL\"} 0" >> "$TEMP_FILE"
      fi

      if [ -n "$REPO_SIZE" ] && [ "$REPO_SIZE" -gt 0 ] 2>/dev/null; then
        echo "backup_repo_size_bytes{dataset=\"$LABEL\",direction=\"$DIRECTION\"} $REPO_SIZE" >> "$TEMP_FILE"
      fi
    done

    # VPS-local offsite repos (TrueNAS→VPS direction)
    for LOCAL_REPO in configs data; do
      LOCAL_PATH="/var/lib/truenas-backups/$LOCAL_REPO.restic"
      if [ -d "$LOCAL_PATH" ]; then
        LOCAL_SIZE=$(du -sb "$LOCAL_PATH" 2>/dev/null | cut -f1)
        if [ -n "$LOCAL_SIZE" ] && [ "$LOCAL_SIZE" -gt 0 ] 2>/dev/null; then
          echo "backup_repo_size_bytes{dataset=\"offsite_$LOCAL_REPO\",direction=\"truenas_to_vps\"} $LOCAL_SIZE" >> "$TEMP_FILE"
        fi
      fi
    done

    mv "$TEMP_FILE" "$TEXTFILE"
    chmod 644 "$TEXTFILE"
    echo "TrueNAS backup metrics written to $TEXTFILE"
  '';

in
{
  config = lib.mkIf (systemSettings.prometheusTruenasBackupEnable or false) {
    # Systemd service
    systemd.services.prometheus-truenas-backup = {
      description = "TrueNAS Restic Backup Metrics Collector";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${truenasBackupScript}";
        User = "akunito";
      };

      preStart = ''
        mkdir -p ${textfileDir}
      '';
    };

    # Timer: daily at 13:00
    systemd.timers.prometheus-truenas-backup = {
      description = "TrueNAS Backup Metrics Timer (daily 13:00)";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "*-*-* 13:00:00";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };
  };
}
