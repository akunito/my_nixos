# TrueNAS Offsite Backup — VPS pulls Docker data + configs from TrueNAS
#
# Pull model: VPS SSHes into TrueNAS, rsyncs to local staging, runs restic locally.
# Two independent jobs with separate restic repos and passwords:
#   - configs: compose files + TrueNAS system config export (daily 15:00)
#   - data:    container data directories (daily 16:00)
#
# Each job writes Prometheus textfile metrics for alerting.
#
# Feature flag: truenasResticBackupEnable = true (in profile config)
#
# Prerequisites:
#   - SSH key at /home/<user>/.ssh/id_ed25519_restic (authorized on TrueNAS)
#   - Password files at /etc/secrets/restic-truenas-{configs,data}
#   - TrueNAS API key at /etc/secrets/truenas-api-key
#   - Restic repos initialized:
#       restic init --repo /var/lib/truenas-backups/configs.restic
#       restic init --repo /var/lib/truenas-backups/data.restic

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  username = userSettings.username;
  truenasHost = systemSettings.truenasResticBackupHost or "192.168.20.200";
  truenasUser = systemSettings.truenasResticBackupUser or "truenas_admin";
  localDir = systemSettings.truenasResticBackupLocalDir or "/var/lib/truenas-backups";
  apiKeyFile = systemSettings.truenasResticBackupApiKeyFile or "/etc/secrets/truenas-api-key";
  sshKey = "/home/${username}/.ssh/id_ed25519_restic";
  sshOpts = "-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -i ${sshKey}";
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  # Helper: create a TrueNAS backup job (rsync + restic + metrics)
  mkTruenasBackup = {
    name,           # Job name: "configs" or "data"
    passwordFile,   # Path to restic password file
    schedule,       # OnCalendar value
    rsyncScript,    # Shell commands for rsync phase
    description,    # Human-readable description
  }: let
    repoDir = "${localDir}/${name}.restic";
    stagingDir = "${localDir}/staging-${name}";
    promFile = "${textfileDir}/truenas_offsite_${name}.prom";

    backupScript = pkgs.writeShellScript "truenas-backup-${name}" ''
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
      LOG_TAG="truenas-backup-${name}"
      START=$NOW
      STATUS=0

      log() { echo "$(date -Iseconds) [$LOG_TAG] $*"; }

      write_metrics() {
        local success=$1
        local duration=$(($(date +%s) - START))
        if [ "$success" -eq 1 ]; then
          cat > "$TEMP_PROM" << METRICS
# HELP truenas_offsite_backup_last_success Unix timestamp of last successful backup
# TYPE truenas_offsite_backup_last_success gauge
truenas_offsite_backup_last_success{job="${name}"} $(date +%s)
# HELP truenas_offsite_backup_status 1 if backup succeeded, 0 if failed
# TYPE truenas_offsite_backup_status gauge
truenas_offsite_backup_status{job="${name}"} 1
# HELP truenas_offsite_backup_duration_seconds Duration of last backup run in seconds
# TYPE truenas_offsite_backup_duration_seconds gauge
truenas_offsite_backup_duration_seconds{job="${name}"} $duration
METRICS
        else
          cat > "$TEMP_PROM" << METRICS
# HELP truenas_offsite_backup_last_success Unix timestamp of last successful backup
# TYPE truenas_offsite_backup_last_success gauge
truenas_offsite_backup_last_success{job="${name}"} 0
# HELP truenas_offsite_backup_status 1 if backup succeeded, 0 if failed
# TYPE truenas_offsite_backup_status gauge
truenas_offsite_backup_status{job="${name}"} 0
# HELP truenas_offsite_backup_duration_seconds Duration of last backup run in seconds
# TYPE truenas_offsite_backup_duration_seconds gauge
truenas_offsite_backup_duration_seconds{job="${name}"} $duration
METRICS
        fi
        mv "$TEMP_PROM" "$PROM_FILE"
        chmod 644 "$PROM_FILE"
      }

      # Ensure directories exist
      mkdir -p "$STAGING"

      # --- Step 1: Check SSH connectivity ---
      log "Checking SSH connectivity to ${truenasUser}@${truenasHost}..."
      if ! ssh ${sshOpts} ${truenasUser}@${truenasHost} "echo ok" >/dev/null 2>&1; then
        log "ERROR: Cannot reach TrueNAS (may be asleep or unreachable)"
        write_metrics 0
        exit 1
      fi

      # --- Step 2: Rsync from TrueNAS ---
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
      description = "TrueNAS Offsite Backup: ${description}";
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
        OnFailure = lib.optional (systemSettings.notificationOnFailureEnable or false) "email-notification@%n.service";
      };
    };
    timer = {
      description = "Timer for TrueNAS Offsite Backup: ${description}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = schedule;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };

  # --- Configs job: compose files + TrueNAS system config export ---
  configsBackup = mkTruenasBackup {
    name = "configs";
    passwordFile = "/etc/secrets/restic-truenas-configs";
    schedule = "*-*-* 15:00:00";
    description = "Docker compose files + TrueNAS system config";
    rsyncScript = ''
      # Rsync compose directory (all docker-compose.yml + env files)
      log "Rsyncing compose configs..."
      rsync -az --delete --timeout=60 \
        -e "ssh ${sshOpts}" \
        --exclude='*.log' --exclude='*.tmp' --exclude='*.cache' \
        ${truenasUser}@${truenasHost}:/mnt/ssdpool/docker/compose/ \
        "$STAGING/docker-configs/" 2>&1

      # Export TrueNAS system config via API
      log "Exporting TrueNAS system config via API..."
      API_KEY=$(cat ${apiKeyFile})
      CONFIG_FILE="$STAGING/truenas-config/truenas-config-$(date +%Y%m%d).tar"
      mkdir -p "$STAGING/truenas-config"

      if curl -sk --max-time 30 \
        -H "Authorization: Bearer $API_KEY" \
        -X POST "https://${truenasHost}/api/v2.0/config/save" \
        -o "$CONFIG_FILE.tmp" 2>/dev/null; then
        if [ -s "$CONFIG_FILE.tmp" ]; then
          mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
          # Remove old config exports (keep 7 days)
          find "$STAGING/truenas-config" -name "truenas-config-*.tar" -mtime +7 -delete 2>/dev/null || true
          log "TrueNAS config saved to $CONFIG_FILE"
        else
          rm -f "$CONFIG_FILE.tmp"
          log "WARNING: TrueNAS config export returned empty file (non-fatal)"
        fi
      else
        rm -f "$CONFIG_FILE.tmp"
        log "WARNING: TrueNAS config API call failed (non-fatal)"
      fi
    '';
  };

  # --- Data job: container data directories ---
  dataBackup = mkTruenasBackup {
    name = "data";
    passwordFile = "/etc/secrets/restic-truenas-data";
    schedule = "*-*-* 16:00:00";
    description = "Docker container data directories";
    rsyncScript = ''
      RSYNC_OPTS="-az --delete --timeout=120"
      EXCLUDES="--exclude='*.log' --exclude='*.tmp' --exclude='*.cache' --exclude='MediaCover/*' --exclude='Backups/*'"

      # Create parent directory for all data rsyncs
      mkdir -p "$STAGING/docker-data"

      # Helper: rsync a directory, non-fatal on failure (some dirs may have permission issues)
      rsync_dir() {
        local src="$1" dst="$2" label="$3"
        shift 3
        log "Rsyncing $label..."
        if ! rsync $RSYNC_OPTS -e "ssh ${sshOpts}" "$@" \
          "${truenasUser}@${truenasHost}:$src" "$dst" 2>&1; then
          log "WARNING: rsync $label had errors (non-fatal)"
        fi
      }

      # Mediarr stack (sonarr, radarr, prowlarr, bazarr, jellyseerr, qbittorrent)
      rsync_dir /mnt/ssdpool/docker/mediarr/ "$STAGING/docker-data/mediarr/" "mediarr" $EXCLUDES

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

      # NPM compose-relative data (if it exists)
      if ssh ${sshOpts} ${truenasUser}@${truenasHost} "test -d /mnt/ssdpool/docker/compose/npm/data" 2>/dev/null; then
        rsync_dir /mnt/ssdpool/docker/compose/npm/data/ "$STAGING/docker-data/npm-compose-data/" "npm compose data"
        rsync_dir /mnt/ssdpool/docker/compose/npm/letsencrypt/ "$STAGING/docker-data/npm-compose-letsencrypt/" "npm compose letsencrypt"
      else
        log "NPM compose-relative data not found (skipping)"
      fi

      # Calibre-Web config
      rsync_dir /mnt/ssdpool/docker/calibre-web/ "$STAGING/docker-data/calibre-web/" "calibre-web"

      # EmulatorJS config
      rsync_dir /mnt/ssdpool/docker/emulatorjs/ "$STAGING/docker-data/emulatorjs/" "emulatorjs"

      # Note: tailscale config is inside compose/ (backed up by configs job)
      # Note: qbittorrent is inside mediarr/ (backed up above)
    '';
  };

in lib.mkIf (systemSettings.truenasResticBackupEnable or false) {
  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${localDir} 0755 ${username} users -"
    "d ${localDir}/staging-configs 0755 ${username} users -"
    "d ${localDir}/staging-data 0755 ${username} users -"
  ];

  # Backup services
  systemd.services.truenas-backup-configs = configsBackup.service;
  systemd.services.truenas-backup-data = dataBackup.service;

  # Backup timers
  systemd.timers.truenas-backup-configs = configsBackup.timer;
  systemd.timers.truenas-backup-data = dataBackup.timer;
}
