# NAS Offsite Backup — VPS pulls Docker data + configs from NAS
#
# Pull model: VPS SSHes into NAS (nas-aku), rsyncs to local staging, runs restic locally.
# Two independent jobs with separate restic repos and passwords:
#   - configs: compose files + NAS system config export (daily 15:00)
#   - data:    container data directories (daily 16:00)
#
# Each job writes Prometheus textfile metrics for alerting.
#
# Feature flag: nasResticBackupEnable = true (in profile config)
#
# Prerequisites:
#   - SSH key at /home/<user>/.ssh/id_ed25519_restic (authorized on NAS akunito user)
#   - Password files at /etc/secrets/restic-truenas-{configs,data}
#     (filename historical — file is on disk, do not rename without restic repo migration)
#   - Restic repos initialized:
#       restic init --repo /var/lib/truenas-backups/configs.restic
#       restic init --repo /var/lib/truenas-backups/data.restic
#     (path historical — disk state preserved across rename)

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  username = userSettings.username;
  nasHost = systemSettings.nasResticBackupHost or "192.168.20.200";
  nasUser = systemSettings.nasResticBackupUser or "akunito";
  localDir = systemSettings.nasResticBackupLocalDir or "/var/lib/truenas-backups";
  # apiKeyFile + nasApiPort removed alongside the config-export block (the
  # legacy TrueNAS UI on port 9443 isn't served by the NixOS NAS).
  sshKey = "/home/${username}/.ssh/id_ed25519_restic";
  sshOpts = "-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -i ${sshKey}";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  # Helper: create a NAS backup job (rsync + restic + metrics)
  mkNasBackup = {
    name,           # Job name: "configs" or "data"
    passwordFile,   # Path to restic password file
    schedule,       # OnCalendar value
    rsyncScript,    # Shell commands for rsync phase
    description,    # Human-readable description
  }: let
    repoDir = "${localDir}/${name}.restic";
    stagingDir = "${localDir}/staging-${name}";
    promFile = "${textfileDir}/nas_offsite_${name}.prom";

    backupScript = pkgs.writeShellScript "nas-backup-${name}" ''
      set -uo pipefail
      export PATH="${lib.makeBinPath [
        pkgs.coreutils pkgs.openssh pkgs.rsync pkgs.curl pkgs.gzip pkgs.findutils
      ]}:$PATH"
      RESTIC="/run/wrappers/bin/restic"
      export RESTIC_PASSWORD_FILE="${passwordFile}"
      REPO="${repoDir}"
      STAGING="${stagingDir}"
      PROM_FILE="${promFile}"
      TEMP_PROM=$(mktemp)
      NOW=$(date +%s)
      LOG_TAG="nas-backup-${name}"
      START=$NOW
      STATUS=0

      log() { echo "$(date -Iseconds) [$LOG_TAG] $*"; }

      write_metrics() {
        local success=$1
        local duration=$(($(date +%s) - START))
        # Read rsync warning count if the rsync phase wrote it; default 0
        local rsync_warnings=0
        if [ -r "$STAGING/.rsync-warnings" ]; then
          rsync_warnings=$(cat "$STAGING/.rsync-warnings" 2>/dev/null || echo 0)
        fi
        if [ "$success" -eq 1 ]; then
          cat > "$TEMP_PROM" << METRICS
# HELP nas_offsite_backup_last_success Unix timestamp of last successful backup
# TYPE nas_offsite_backup_last_success gauge
nas_offsite_backup_last_success{job="${name}"} $(date +%s)
# HELP nas_offsite_backup_status 1 if backup succeeded, 0 if failed
# TYPE nas_offsite_backup_status gauge
nas_offsite_backup_status{job="${name}"} 1
# HELP nas_offsite_backup_duration_seconds Duration of last backup run in seconds
# TYPE nas_offsite_backup_duration_seconds gauge
nas_offsite_backup_duration_seconds{job="${name}"} $duration
# HELP nas_offsite_backup_rsync_warnings Number of rsync_dir calls that hit non-fatal errors
# TYPE nas_offsite_backup_rsync_warnings gauge
nas_offsite_backup_rsync_warnings{job="${name}"} $rsync_warnings
METRICS
        else
          cat > "$TEMP_PROM" << METRICS
# HELP nas_offsite_backup_last_success Unix timestamp of last successful backup
# TYPE nas_offsite_backup_last_success gauge
nas_offsite_backup_last_success{job="${name}"} 0
# HELP nas_offsite_backup_status 1 if backup succeeded, 0 if failed
# TYPE nas_offsite_backup_status gauge
nas_offsite_backup_status{job="${name}"} 0
# HELP nas_offsite_backup_duration_seconds Duration of last backup run in seconds
# TYPE nas_offsite_backup_duration_seconds gauge
nas_offsite_backup_duration_seconds{job="${name}"} $duration
# HELP nas_offsite_backup_rsync_warnings Number of rsync_dir calls that hit non-fatal errors
# TYPE nas_offsite_backup_rsync_warnings gauge
nas_offsite_backup_rsync_warnings{job="${name}"} $rsync_warnings
METRICS
        fi
        mv "$TEMP_PROM" "$PROM_FILE"
        chmod 644 "$PROM_FILE"
      }

      # Ensure directories exist
      mkdir -p "$STAGING"

      # --- Step 1: Check SSH connectivity ---
      log "Checking SSH connectivity to ${nasUser}@${nasHost}..."
      if ! ssh ${sshOpts} ${nasUser}@${nasHost} "echo ok" >/dev/null 2>&1; then
        log "ERROR: Cannot reach NAS (may be asleep or unreachable)"
        write_metrics 0
        exit 1
      fi

      # --- Step 2: Rsync from NAS ---
      log "Starting rsync: ${description}"
      ${rsyncScript}

      # --- Step 3: Restic backup of staging dir ---
      log "Running restic backup of $STAGING..."
      $RESTIC -r "$REPO" backup "$STAGING" --verbose 2>&1

      # --- Step 4: Prune old snapshots ---
      log "Pruning snapshots (keep-daily 2, keep-weekly 1, keep-monthly 1)..."
      $RESTIC -r "$REPO" forget \
        --keep-daily 2 --keep-weekly 1 --keep-monthly 1 \
        --prune 2>&1

      # --- Step 5: Write success metrics ---
      log "Backup complete"
      write_metrics 1
    '';
  in {
    service = {
      description = "NAS Offsite Backup: ${description}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        User = username;
        Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/bin";
        TimeoutStartSec = "2h";
        Restart = "on-failure";
        RestartSec = "5min";
      };
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = "30min";
        OnFailure = lib.optional (systemSettings.notificationOnFailureEnable or false) "notify-failure@%n.service";
      };
      # One-time cleanup so node-exporter stops publishing stale legacy series
      # after the truenas→nas rename. Safe to run every invocation.
      preStart = ''
        rm -f ${textfileDir}/truenas_offsite_${name}.prom
      '';
    };
    timer = {
      description = "Timer for NAS Offsite Backup: ${description}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = schedule;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };

  # --- Configs job: compose files only (NAS system config export retired
  # after AINF-336 migration — TrueNAS UI on port 9443 is not served by the
  # NixOS NAS; the API-export block was a no-op + WARNING noise on every run) ---
  configsBackup = mkNasBackup {
    name = "configs";
    passwordFile = "/etc/secrets/restic-truenas-configs";  # path historical, file is on disk
    schedule = "*-*-* 15:00:00";
    description = "Docker compose files (NixOS NAS — no API config export)";
    rsyncScript = ''
      # Rsync compose directory (all docker-compose.yml + env files)
      log "Rsyncing compose configs..."
      rsync -az --delete --timeout=60 \
        -e "ssh ${sshOpts}" \
        --exclude='*.log' --exclude='*.tmp' --exclude='*.cache' \
        ${nasUser}@${nasHost}:/mnt/ssdpool/docker/compose/ \
        "$STAGING/docker-configs/" 2>&1
    '';
  };

  # --- Data job: container data directories ---
  dataBackup = mkNasBackup {
    name = "data";
    passwordFile = "/etc/secrets/restic-truenas-data";  # path historical, file is on disk
    schedule = "*-*-* 16:00:00";
    description = "Docker container data directories";
    rsyncScript = ''
      RSYNC_OPTS="-az --delete --timeout=120"
      EXCLUDES="--exclude='*.log' --exclude='*.tmp' --exclude='*.cache' --exclude='MediaCover/*' --exclude='Backups/*'"

      # Create parent directory for all data rsyncs
      mkdir -p "$STAGING/docker-data"

      # Track rsync warnings so the failure surface is visible in metrics later.
      RSYNC_WARNINGS=0

      # Helper: rsync a directory, non-fatal on failure (some dirs may have permission issues).
      # WARNINGS are counted so the metric layer can surface coverage gaps.
      rsync_dir() {
        local src="$1" dst="$2" label="$3"
        shift 3
        log "Rsyncing $label..."
        if ! rsync $RSYNC_OPTS -e "ssh ${sshOpts}" "$@" \
          "${nasUser}@${nasHost}:$src" "$dst" 2>&1; then
          log "WARNING: rsync $label had errors (non-fatal)"
          RSYNC_WARNINGS=$((RSYNC_WARNINGS + 1))
        fi
      }

      # Mediarr stack (sonarr, radarr, prowlarr, bazarr, jellyseerr, qbittorrent).
      # Exclude regenerable container-internal junk that's owned by sub-UIDs
      # and would otherwise produce "Permission denied" rsync warnings.
      rsync_dir /mnt/ssdpool/docker/mediarr/ "$STAGING/docker-data/mediarr/" "mediarr" $EXCLUDES \
        --exclude='calibre-server/config/.XDG/' \
        --exclude='calibre-server/config/.cache/' \
        --exclude='calibre-server/config/.dbus/' \
        --exclude='calibre-server/config/.config/pulse/' \
        --exclude='calibre-server/config/.config/calibre/fonts/' \
        --exclude='calibre-server/config/.config/calibre/plugins/' \
        --exclude='qbittorrent/qBittorrent/logs/'

      # Jellyfin config
      rsync_dir /mnt/ssdpool/docker/jellyfin/etc/ "$STAGING/docker-data/jellyfin-etc/" "jellyfin config" \
        --exclude='var-cache/*' --exclude='var-log/*' --exclude='*.log' --exclude='*.tmp'

      # Jellyfin library metadata
      rsync_dir /mnt/ssdpool/docker/jellyfin/var-lib/ "$STAGING/docker-data/jellyfin-var-lib/" "jellyfin data" \
        --exclude='*.log' --exclude='*.tmp' --exclude='*.cache'

      # Gluetun VPN state
      rsync_dir /mnt/ssdpool/docker/gluetun/ "$STAGING/docker-data/gluetun/" "gluetun"

      # NPM data (ZFS dataset)
      rsync_dir /mnt/ssdpool/docker/npm/ "$STAGING/docker-data/npm/" "npm"

      # NPM compose-relative data (if it exists).
      # /letsencrypt is owned root:700 — akunito reads it via POSIX ACL on the
      # ssdpool/docker dataset (acltype=posixacl + setfacl -R u:akunito:rX).
      if ssh ${sshOpts} ${nasUser}@${nasHost} "test -d /mnt/ssdpool/docker/compose/npm/data" 2>/dev/null; then
        rsync_dir /mnt/ssdpool/docker/compose/npm/data/ "$STAGING/docker-data/npm-compose-data/" "npm compose data"
        rsync_dir /mnt/ssdpool/docker/compose/npm/letsencrypt/ "$STAGING/docker-data/npm-compose-letsencrypt/" "npm compose letsencrypt"
      else
        log "NPM compose-relative data not found (skipping)"
      fi

      # Surface rsync warning count for the calling backupScript to emit as metric.
      log "rsync warning count: $RSYNC_WARNINGS"
      echo "$RSYNC_WARNINGS" > "$STAGING/.rsync-warnings"

      # Note: calibre-web and emulatorjs are VPS services, not NAS — not backed up here
      # Note: tailscale config is inside compose/ (backed up by configs job)
      # Note: qbittorrent is inside mediarr/ (backed up above)
    '';
  };

in lib.mkIf (systemSettings.nasResticBackupEnable or false) {
  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${localDir} 0755 ${username} users -"
    "d ${localDir}/staging-configs 0755 ${username} users -"
    "d ${localDir}/staging-data 0755 ${username} users -"
  ];

  # Backup services
  systemd.services.nas-backup-configs = configsBackup.service;
  systemd.services.nas-backup-data = dataBackup.service;

  # Backup timers
  systemd.timers.nas-backup-configs = configsBackup.timer;
  systemd.timers.nas-backup-data = dataBackup.timer;
}
