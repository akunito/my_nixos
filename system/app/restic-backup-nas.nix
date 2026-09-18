# NAS Offsite Backup — VPS pulls Docker data + configs from NAS
#
# Pull model: VPS SSHes into NAS (nas-aku), rsyncs to local staging, runs restic locally.
# Three independent jobs with separate restic repos and passwords:
#   - configs:  compose files (daily 17:30) — gameservers/ excluded, see akucraft
#   - data:     container data directories (daily 18:00)
#   - akucraft: the Minecraft worlds under compose/gameservers/ (daily 18:30),
#               split out on 2026-09-18 because they are 9.4 GB of world data in
#               a tree whose other 15 directories total 190 MB, and because the
#               files a restore actually needs were unreadable — see the
#               nasBackupAclPaths / nas-backup-acl service on the NAS.
# Scheduled inside the NAS awake window (16:00-23:00); NAS can't be WoL-woken from S3.
#
# Each job writes Prometheus textfile metrics for alerting.
#
# Feature flag: nasResticBackupEnable = true (in profile config)
#
# Prerequisites:
#   - SSH key at /home/<user>/.ssh/id_ed25519_restic (authorized on NAS akunito user)
#   - Password files at /etc/secrets/restic-truenas-{configs,data}
#     (filename historical — file is on disk, do not rename without restic repo migration)
#     /etc/secrets/restic-akucraft is declared from secrets.resticAkucraftPassword
#     instead, like the restic-backup-vps.nix repos.
#   - Restic repos initialized:
#       restic init --repo /var/lib/truenas-backups/configs.restic
#       restic init --repo /var/lib/truenas-backups/data.restic
#       restic init --repo /var/lib/truenas-backups/akucraft.restic
#     (configs/data paths historical — disk state preserved across rename)
#   - The NAS grants akunito read access to the gameservers tree
#     (nasBackupAclPaths in NAS_PROD-config.nix). Without it the akucraft job
#     copies the worlds minus level.dat, playerdata and skinrestorer state, i.e.
#     a backup that cannot be restored, and says so only as an rsync warning.

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
  # Separate flag so the VPS job can be switched on only after the NAS has the
  # ACL service deployed; without it the worlds copy incomplete and silent.
  akucraftEnabled = systemSettings.nasResticBackupAkucraftEnable or false;

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

      # Default rsync options; a job's rsyncScript may override them before
      # its first rsync_dir call.
      RSYNC_OPTS="-az --delete --timeout=120"

      # Number of rsync_dir calls that ended in a warning. Written to
      # $STAGING/.rsync-warnings after the rsync phase and picked up by
      # write_metrics as nas_offsite_backup_rsync_warnings.
      RSYNC_WARNINGS=0

      # Rsync one directory off the NAS. Non-fatal: a single unreadable source
      # must not cost us the whole snapshot. Transient CONNECTION failures are
      # retried, because a single refused connect used to silently drop one
      # source directory from the backup while restic still took a snapshot
      # (npm on 2026-09-16, jellyfin data on 2026-09-17, both caused by the
      # pfSense-routed LAN IP that VPS_PROD no longer uses). rsync exit codes
      # 10 (socket I/O), 12 (protocol/stream), 30 and 35 (timeouts) and 255
      # (ssh itself failed) are network problems and are worth another try;
      # 23 (partial transfer / permission denied) and 24 (vanished files) are
      # not, and retrying them only wastes minutes on large trees.
      rsync_dir() {
        local src="$1" dst="$2" label="$3"
        shift 3
        local attempt rc=0
        for attempt in 1 2 3; do
          if [ "$attempt" -eq 1 ]; then log "Rsyncing $label..."; else log "Rsyncing $label (retry $((attempt - 1)))..."; fi
          rsync $RSYNC_OPTS -e "ssh ${sshOpts}" "$@" \
            "${nasUser}@${nasHost}:$src" "$dst" 2>&1
          rc=$?
          [ "$rc" -eq 0 ] && return 0
          case "$rc" in
            10|12|30|35|255)
              log "rsync $label hit a connection error (rc=$rc), retrying in 10s"
              sleep 10
              ;;
            *) break ;;
          esac
        done
        log "WARNING: rsync $label had errors (non-fatal, rc=$rc)"
        RSYNC_WARNINGS=$((RSYNC_WARNINGS + 1))
        return "$rc"
      }

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

      log "rsync warning count: $RSYNC_WARNINGS"
      echo "$RSYNC_WARNINGS" > "$STAGING/.rsync-warnings"

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
    schedule = "*-*-* 17:30:00";  # NAS awake 16:00-23:00; buffer past wake + post-resume docker race
    description = "Docker compose files (NixOS NAS — no API config export)";
    rsyncScript = ''
      # Rsync compose directory (all docker-compose.yml + env files).
      # tailscale/state/ holds tailscaled.state (node key) + derpmap.cached.json,
      # both root-owned 0600 inside the rootful container — unreadable to
      # akunito on NAS and not appropriate to back up:
      #   * node key proliferation across copies is undesirable;
      #     re-authenticating a restored NAS to headscale is the standard
      #     recovery path.
      #   * derpmap.cached.json is regenerated by the tailscale daemon.
      # Excluding the dir avoids the rsync code 23 "partial transfer"
      # warning on every run.
      # Goes through rsync_dir like the data job: before 2026-09-18 this was a
      # bare rsync whose failure was neither retried nor counted, so
      # nas_offsite_backup_rsync_warnings{job="configs"} could never leave 0
      # even when the compose tree had not been copied at all.
      # gameservers/ is excluded and owned by the akucraft job below. It is 9.4 GB
      # of Minecraft world data in a tree whose other 15 directories total 190 MB,
      # and its level.dat / playerdata / skinrestorer files are uid 100999 mode
      # 0600 (rootless-docker subuid), unreadable to akunito. Copying it here
      # produced a world backup that could never be restored, and the resulting
      # rsync IO error made rsync skip --delete on every run, so the staging copy
      # never dropped deleted files either. Invisible until 2026-09-18, because
      # this job did not count rsync warnings at all.
      RSYNC_OPTS="-az --delete --timeout=60"
      rsync_dir /mnt/ssdpool/docker/compose/ "$STAGING/docker-configs/" "compose configs" \
        --exclude='*.log' --exclude='*.tmp' --exclude='*.cache' \
        --exclude='tailscale/state/' \
        --exclude='gameservers/'
    '';
  };

  # --- Data job: container data directories ---
  dataBackup = mkNasBackup {
    name = "data";
    passwordFile = "/etc/secrets/restic-truenas-data";  # path historical, file is on disk
    schedule = "*-*-* 18:00:00";  # NAS awake 16:00-23:00; runs after the configs job
    description = "Docker container data directories";
    rsyncScript = ''
      RSYNC_OPTS="-az --delete --timeout=120"
      EXCLUDES="--exclude='*.log' --exclude='*.tmp' --exclude='*.cache' --exclude='MediaCover/*' --exclude='Backups/*'"

      # Create parent directory for all data rsyncs
      mkdir -p "$STAGING/docker-data"

      # Mediarr stack (sonarr, radarr, prowlarr, bazarr, jellyseerr, qbittorrent).
      # Exclude regenerable container-internal junk that's owned by sub-UIDs
      # and would otherwise produce "Permission denied" rsync warnings.
      # bazarr/cache/ — subtitle search cache, root-owned 0600 inside the
      # rootful bazarr container, unreadable to akunito on NAS. Cache only,
      # regenerable; same treatment as tailscale/state/ in the configs job.
      rsync_dir /mnt/ssdpool/docker/mediarr/ "$STAGING/docker-data/mediarr/" "mediarr" $EXCLUDES \
        --exclude='*/asp/' \
        --exclude='calibre-server/config/.XDG/' \
        --exclude='calibre-server/config/.cache/' \
        --exclude='calibre-server/config/.dbus/' \
        --exclude='calibre-server/config/.config/pulse/' \
        --exclude='calibre-server/config/.config/calibre/fonts/' \
        --exclude='calibre-server/config/.config/calibre/plugins/' \
        --exclude='qbittorrent/qBittorrent/logs/' \
        --exclude='bazarr/cache/'

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

      # Note: calibre-web and emulatorjs are VPS services, not NAS — not backed up here
      # Note: tailscale config is inside compose/ (backed up by configs job)
      # Note: qbittorrent is inside mediarr/ (backed up above)
    '';
  };

  # --- AkuCraft job: the Minecraft worlds under compose/gameservers/ ---
  # Kept out of the configs job (which is meant to be compose files) and out of
  # the data job (which covers /mnt/ssdpool/docker/*), because this is ~5 GB of
  # game state with its own lifetime and its own restore story.
  #
  # Included: every world (data/world*, master/, master.tgz, world-seed*), the
  # server configs, the compose files and the run scripts.
  # Excluded: everything a fresh server would fetch or regenerate — mods,
  # libraries, versions, automodpack, the bluemap/squaremap render caches, logs,
  # crash reports — and akucraft-solo/runs/, which is 2.5 GB of superseded past
  # solo worlds already sitting on the NAS. Flip that exclude if a past run ever
  # needs to survive the NAS itself.
  akucraftBackup = mkNasBackup {
    name = "akucraft";
    passwordFile = "/etc/secrets/restic-akucraft";
    schedule = "*-*-* 18:30:00";  # NAS awake 16:00-23:00; runs after the data job
    description = "AkuCraft Minecraft worlds (NAS gameservers)";
    rsyncScript = ''
      RSYNC_OPTS="-az --delete --timeout=120"
      mkdir -p "$STAGING/gameservers"

      rsync_dir /mnt/ssdpool/docker/compose/gameservers/ "$STAGING/gameservers/" "akucraft gameservers" \
        --exclude='*/data/mods/' \
        --exclude='*/data/libraries/' \
        --exclude='*/data/versions/' \
        --exclude='*/data/automodpack/' \
        --exclude='*/data/bluemap/' \
        --exclude='*/data/squaremap/' \
        --exclude='*/data/logs/' \
        --exclude='*/data/crash-reports/' \
        --exclude='*/data/dynamic-data-pack-cache/' \
        --exclude='*/runs/' \
        --exclude='*.jar' --exclude='*.log' --exclude='*.tmp' --exclude='*.cache'

      # Note: a server that happens to be running is copied live. The AkuCraft
      # servers idle-stop, so in practice the tree is quiescent at 18:30; if that
      # stops being true, have the bot issue save-off/save-all first.
    '';
  };

in lib.mkIf (systemSettings.nasResticBackupEnable or false) {
  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${localDir} 0755 ${username} users -"
    "d ${localDir}/staging-configs 0755 ${username} users -"
    "d ${localDir}/staging-data 0755 ${username} users -"
  ] ++ lib.optionals akucraftEnabled [
    "d ${localDir}/staging-akucraft 0755 ${username} users -"
  ];

  # Declared like the restic-backup-vps.nix repos, so a rebuilt VPS still has it
  # (the historical restic-truenas-* files are hand-placed and would not).
  environment.etc = lib.mkIf (akucraftEnabled && (systemSettings.resticAkucraftPassword or "") != "") {
    "secrets/restic-akucraft" = {
      text = systemSettings.resticAkucraftPassword;
      mode = "0600"; user = "root"; group = "root";
    };
  };

  # Backup services
  systemd.services.nas-backup-configs = configsBackup.service;
  systemd.services.nas-backup-data = dataBackup.service;
  systemd.services.nas-backup-akucraft = lib.mkIf akucraftEnabled akucraftBackup.service;

  # Backup timers
  systemd.timers.nas-backup-configs = configsBackup.timer;
  systemd.timers.nas-backup-data = dataBackup.timer;
  systemd.timers.nas-backup-akucraft = lib.mkIf akucraftEnabled akucraftBackup.timer;
}
