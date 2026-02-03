{ lib, userSettings, systemSettings, pkgs, authorizedKeys ? [], ... }:

let
  # Script to export backup metrics for Prometheus textfile collector
  backupMetricsScript = pkgs.writeShellScript "backup-metrics" ''
    set -e
    TEXTFILE_DIR="/var/lib/prometheus-node-exporter/textfile"
    METRICS_FILE="$TEXTFILE_DIR/backup.prom"
    TEMP_FILE="$TEXTFILE_DIR/backup.prom.tmp"

    # Ensure directory exists
    mkdir -p "$TEXTFILE_DIR"

    # Initialize metrics file
    echo "# HELP backup_last_success_timestamp Unix timestamp of last successful backup" > "$TEMP_FILE"
    echo "# TYPE backup_last_success_timestamp gauge" >> "$TEMP_FILE"
    echo "# HELP backup_age_seconds Seconds since last successful backup" >> "$TEMP_FILE"
    echo "# TYPE backup_age_seconds gauge" >> "$TEMP_FILE"
    echo "# HELP backup_snapshots_total Total number of snapshots in repository" >> "$TEMP_FILE"
    echo "# TYPE backup_snapshots_total gauge" >> "$TEMP_FILE"
    echo "# HELP backup_repository_healthy Whether the repository is accessible (1=yes, 0=no)" >> "$TEMP_FILE"
    echo "# TYPE backup_repository_healthy gauge" >> "$TEMP_FILE"

    # Check restic repository
    export RESTIC_REPOSITORY="${systemSettings.backupMonitoringRepo or "/mnt/DATA_4TB/backups/NixOS_homelab/Home.restic/"}"
    export RESTIC_PASSWORD_FILE="${systemSettings.backupMonitoringPasswordFile or "/home/${userSettings.username}/myScripts/restic.key"}"

    NOW=$(date +%s)

    # Try to get snapshots info
    if SNAPSHOTS=$(/run/wrappers/bin/restic snapshots --json 2>/dev/null); then
      SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | ${pkgs.jq}/bin/jq 'length')
      LAST_BACKUP=$(echo "$SNAPSHOTS" | ${pkgs.jq}/bin/jq -r 'sort_by(.time) | last | .time // empty')

      if [ -n "$LAST_BACKUP" ]; then
        LAST_TIMESTAMP=$(date -d "$LAST_BACKUP" +%s 2>/dev/null || echo "0")
        AGE_SECONDS=$((NOW - LAST_TIMESTAMP))

        echo "backup_last_success_timestamp{repo=\"home\"} $LAST_TIMESTAMP" >> "$TEMP_FILE"
        echo "backup_age_seconds{repo=\"home\"} $AGE_SECONDS" >> "$TEMP_FILE"
      else
        echo "backup_last_success_timestamp{repo=\"home\"} 0" >> "$TEMP_FILE"
        echo "backup_age_seconds{repo=\"home\"} 999999999" >> "$TEMP_FILE"
      fi

      echo "backup_snapshots_total{repo=\"home\"} $SNAPSHOT_COUNT" >> "$TEMP_FILE"
      echo "backup_repository_healthy{repo=\"home\"} 1" >> "$TEMP_FILE"
    else
      echo "backup_last_success_timestamp{repo=\"home\"} 0" >> "$TEMP_FILE"
      echo "backup_age_seconds{repo=\"home\"} 999999999" >> "$TEMP_FILE"
      echo "backup_snapshots_total{repo=\"home\"} 0" >> "$TEMP_FILE"
      echo "backup_repository_healthy{repo=\"home\"} 0" >> "$TEMP_FILE"
    fi

    # Atomically move temp file to final location
    mv "$TEMP_FILE" "$METRICS_FILE"
  '';
in
{
  # ====================== Wrappers ======================
  # Create restic user
  users.users.restic = lib.mkIf (systemSettings.resticWrapper == true) {
    isNormalUser = true;
  };
  # Wrapper for restic
  security.wrappers.restic = lib.mkIf (systemSettings.resticWrapper == true) {
    source = "/run/current-system/sw/bin/restic";
    owner = userSettings.username; # Sets the owner of the restic binary (see below u=rwx)
    group = "wheel";
    permissions = "u=rwx,g=,o=";
    capabilities = "cap_dac_read_search=+ep";
  };

  # ====================== Local Backup settings ======================
  # Systemd service to execute sh script
  # Main user | Every 6 hours | Script includes wrapper for restic (config on sudo.nix)
  systemd.services.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.homeBackupExecStart;
      User = systemSettings.homeBackupUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
    unitConfig = { # Call next service on success
      OnSuccess = systemSettings.homeBackupCallNext;
    };
  };
  systemd.timers.home_backup = lib.mkIf (systemSettings.homeBackupEnable == true) {
    description = systemSettings.homeBackupTimerDescription;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = systemSettings.homeBackupOnCalendar; # Every 6 hours
      Persistent = true;
    };
  };


  # ====================== Remote Backup settings ======================
  # Systemd service to run after home_backup
  systemd.services.remote_backup = lib.mkIf (systemSettings.remoteBackupEnable == true) {
    description = systemSettings.remoteBackupDescription;
    serviceConfig = {
      Type = "simple";
      ExecStart = systemSettings.remoteBackupExecStart;
      User = systemSettings.remoteBackupUser;
      Environment = "PATH=/run/current-system/sw/bin:/usr/bin:/bin";
    };
  };

  # ====================== Backup Monitoring ======================
  # Export backup metrics for Prometheus textfile collector
  systemd.services.backup-metrics = lib.mkIf (systemSettings.backupMonitoringEnable or false) {
    description = "Export backup metrics for Prometheus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupMetricsScript}";
      User = userSettings.username;
    };
  };

  systemd.timers.backup-metrics = lib.mkIf (systemSettings.backupMonitoringEnable or false) {
    description = "Timer for backup metrics export";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = systemSettings.backupMonitoringOnCalendar or "hourly";
      Persistent = true;
    };
  };
}
