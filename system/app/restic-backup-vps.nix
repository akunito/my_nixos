# VPS Restic Backup to TrueNAS via SFTP
#
# Automated backup of VPS data to TrueNAS (hddpool/vps-backups) via Tailscale SFTP.
# Three separate repositories with independent schedules and retention policies:
#   - databases: PostgreSQL + MariaDB dumps (daily at 18:00, keep 30 days)
#   - services:  Docker configs, Headscale state, secrets (daily at 19:00, keep 30 days)
#   - nextcloud: Nextcloud data directory (weekly Sunday at 20:00, keep 14 days)
#
# Feature flag: vpsResticBackupEnable = true (in profile config)
#
# Prerequisites:
#   - SSH key at /home/<user>/.ssh/id_ed25519_restic (passwordless, for truenas_admin)
#   - Password files at /etc/secrets/restic-{databases,services,nextcloud}
#   - Restic repos initialized on TrueNAS at /mnt/hddpool/vps-backups/*.restic
#   - TrueNAS reachable via Tailscale at vpsResticTarget IP

{ lib, pkgs, systemSettings, userSettings, ... }:

let
  username = userSettings.username;
  target = systemSettings.vpsResticTarget or "100.64.0.9";
  targetUser = systemSettings.vpsResticTargetUser or "truenas_admin";
  sshKey = "/home/${username}/.ssh/id_ed25519_restic";
  sftpCommand = "ssh -i ${sshKey} ${targetUser}@${target} -s sftp";
  repoBase = "sftp:${targetUser}@${target}:/mnt/hddpool/vps-backups";

  # Helper to create a restic backup service + timer
  mkResticBackup = {
    name,           # Service name suffix (e.g., "databases")
    passwordFile,   # Path to restic password file
    repoSuffix,     # Repo directory name (e.g., "databases.restic")
    backupPaths,    # List of paths to back up
    excludes ? [],  # List of --exclude patterns
    tags ? [],      # List of --tag values
    schedule,       # OnCalendar value
    retentionDays,  # --keep-within value in days
    retentionPolicy ? "", # Additional retention flags (optional)
    preScript ? "", # Commands to run before backup (e.g., pg_dumpall)
    description,    # Human-readable description
  }: let
    repo = "${repoBase}/${repoSuffix}";
    excludeFlags = lib.concatMapStrings (e: " --exclude \"${e}\"") excludes;
    tagFlags = lib.concatMapStrings (t: " --tag ${t}") tags;
    retentionExtra = if retentionPolicy != "" then " ${retentionPolicy}" else "";

    backupScript = pkgs.writeShellScript "vps-restic-${name}" ''
      set -euo pipefail
      export RESTIC_PASSWORD_FILE="${passwordFile}"
      RESTIC="/run/wrappers/bin/restic"
      REPO="${repo}"
      SFTP_CMD="${sftpCommand}"
      LOG_TAG="vps-restic-${name}"

      log() { echo "$(date -Iseconds) [$LOG_TAG] $*"; }

      log "Starting backup: ${description}"

      ${lib.optionalString (preScript != "") ''
        log "Running pre-backup script..."
        ${preScript}
      ''}

      # Run backup
      log "Backing up: ${lib.concatStringsSep " " backupPaths}"
      $RESTIC -r "$REPO" -o "sftp.command=$SFTP_CMD" \
        backup ${lib.concatStringsSep " " backupPaths}${excludeFlags}${tagFlags} \
        --verbose 2>&1

      # Prune old snapshots
      log "Pruning snapshots (keep-within ${toString retentionDays}d${retentionExtra})..."
      $RESTIC -r "$REPO" -o "sftp.command=$SFTP_CMD" \
        forget --keep-within ${toString retentionDays}d${retentionExtra} --prune 2>&1

      log "Backup complete"
    '';
  in {
    service = {
      description = "VPS Restic Backup: ${description}";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        User = username;
        Environment = "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/bin";
        TimeoutStartSec = "4h";
        # Retry on failure (network glitches)
        Restart = "on-failure";
        RestartSec = "5min";
        # Limit retries
        StartLimitBurst = 3;
        StartLimitIntervalSec = "30min";
      };
      unitConfig = {
        OnFailure = lib.optional (systemSettings.notificationOnFailureEnable or false) "email-notification@%n.service";
      };
    };
    timer = {
      description = "Timer for VPS Restic Backup: ${description}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = schedule;
        Persistent = true;
        RandomizedDelaySec = "10min";
      };
    };
  };

  # Define the three backup jobs
  databasesBackup = mkResticBackup {
    name = "databases";
    passwordFile = "/etc/secrets/restic-databases";
    repoSuffix = "databases.restic";
    backupPaths = [ "/var/backups/databases" ];
    tags = [ "databases" "postgresql" "mariadb" ];
    schedule = "*-*-* 18:00:00";
    retentionDays = 30;
    retentionPolicy = "--keep-monthly 3";
    description = "PostgreSQL + MariaDB database dumps";
  };

  servicesBackup = mkResticBackup {
    name = "services";
    passwordFile = "/etc/secrets/restic-services";
    repoSuffix = "services.restic";
    backupPaths = [
      "/home/${username}/.homelab"
      "/home/${username}/.local/share/docker/volumes/uptime-kuma_kuma_data/_data"
      "/var/lib/headscale"
      "/etc/secrets"
    ];
    excludes = [ "*.log" "*.tmp" "*.cache" ];
    tags = [ "services" "docker" "headscale" ];
    schedule = "*-*-* 19:00:00";
    retentionDays = 30;
    retentionPolicy = "--keep-monthly 3";
    description = "Docker configs, Headscale state, secrets, Uptime Kuma data";
  };

  nextcloudBackup = mkResticBackup {
    name = "nextcloud";
    passwordFile = "/etc/secrets/restic-nextcloud";
    repoSuffix = "nextcloud.restic";
    backupPaths = [ "/var/lib/nextcloud-data" ];
    excludes = [ "*.log" "*.part" "upload_tmp/*" ];
    tags = [ "nextcloud" ];
    schedule = "Sun *-*-* 20:00:00";
    retentionDays = 14;
    retentionPolicy = "--keep-monthly 2";
    description = "Nextcloud user data";
  };

in lib.mkIf (systemSettings.vpsResticBackupEnable or false) {
  # Backup services
  systemd.services.vps-restic-databases = databasesBackup.service;
  systemd.services.vps-restic-services = servicesBackup.service;
  systemd.services.vps-restic-nextcloud = nextcloudBackup.service;

  # Backup timers
  systemd.timers.vps-restic-databases = databasesBackup.timer;
  systemd.timers.vps-restic-services = servicesBackup.timer;
  systemd.timers.vps-restic-nextcloud = nextcloudBackup.timer;
}
