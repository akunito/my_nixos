# VPS Restic Backup to TrueNAS via SFTP
#
# Automated backup of VPS data to TrueNAS via Tailscale SFTP.
# Four separate backup jobs with independent schedules and retention policies:
#   - databases:  PostgreSQL + MariaDB dumps (daily at 19:00, keep 30 days) → extpool
#   - services:   Docker configs, Headscale, Vaultwarden, secrets (daily at 19:30, keep 30 days) → extpool
#   - nextcloud:  Nextcloud data directory (weekly Sunday at 20:00, keep 14 days) → extpool
#   - libraries:  RomM ROMs + Calibre books ~260GB (weekly Sunday at 20:30, keep 30 days) → extpool
#
# All VPS backups target extpool/vps-backups/ on TrueNAS.
#
# Schedule rationale: TrueNAS sleeps 23:00-11:00. Backups run 19:00-22:00 window.
#
# Feature flag: vpsResticBackupEnable = true (in profile config)
#
# Prerequisites:
#   - SSH key at /home/<user>/.ssh/id_ed25519_restic (passwordless, for akunito on NAS)
#   - Password files at /etc/secrets/restic-{databases,services,nextcloud}
#   - Restic repos initialized on TrueNAS:
#     - /mnt/extpool/vps-backups/databases.restic
#     - /mnt/extpool/vps-backups/services.restic
#     - /mnt/extpool/vps-backups/nextcloud.restic
#   - TrueNAS reachable via Tailscale at vpsResticTarget IP

{ lib, pkgs, systemSettings, userSettings, ... }:

let
  username = userSettings.username;
  target = systemSettings.vpsResticTarget or "nas-aku";  # NAS Tailscale hostname
  targetUser = systemSettings.vpsResticTargetUser or "akunito";
  sshKey = "/home/${username}/.ssh/id_ed25519_restic";
  sftpCommand = "ssh -i ${sshKey} -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${targetUser}@${target} -s sftp";
  repoBase = "sftp:${targetUser}@${target}:/mnt/extpool/vps-backups";

  # Helper to create a restic backup service + timer
  mkResticBackup = {
    name,           # Service name suffix (e.g., "databases")
    passwordFile,   # Path to restic password file
    repoSuffix,     # Repo directory name (e.g., "databases.restic")
    # repoBase is inherited from outer let (all VPS backups on extpool)
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
      # Use the security.wrappers restic binary — it carries
      # CAP_DAC_READ_SEARCH so this user-level service can read root-owned
      # source files (DB dumps in /var/backups/databases, /etc/secrets,
      # /var/lib/{headscale,vaultwarden}, container-owned dirs under
      # ~/.openclaw and ~/.homelab). Switching to the raw binary on
      # 2026-05-14 (d46a962) broke databases/services/libraries backups
      # because they relied on that capability. The nextcloud backup
      # additionally needs filesystem ACLs because restic 0.18.x uses
      # access(2) which ignores process capabilities (issues #2447, #2563)
      # — those ACLs are applied by vps-backup-source-acls.service below.
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
        --limit-upload 50000 --verbose 2>&1

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
        # Permission model: /run/wrappers/bin/restic carries
        # CAP_DAC_READ_SEARCH (file capability) so it bypasses DAC checks at
        # the syscall level, allowing this user-level service to read
        # root-owned source files. The wrapper covers databases + services
        # + libraries. The nextcloud backup additionally needs POSIX ACLs
        # because restic 0.18.x uses access(2) on directory entries which
        # ignores process capabilities for non-root users (issues #2447,
        # #2563) — see vps-backup-source-acls.service below.
      };
      unitConfig = {
        # Limit retries (must be in [Unit], not [Service])
        StartLimitBurst = 3;
        StartLimitIntervalSec = "30min";
        OnFailure = lib.optional (systemSettings.notificationOnFailureEnable or false) "notify-failure@%n.service";
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

  # Define the four backup jobs (all target extpool/vps-backups/)
  databasesBackup = mkResticBackup {
    name = "databases";
    passwordFile = "/etc/secrets/restic-databases";
    repoSuffix = "databases.restic";
    backupPaths = [ "/var/backups/databases" ];
    tags = [ "databases" "postgresql" "mariadb" ];
    schedule = "*-*-* 19:00:00";
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
      "/home/${username}/.openclaw"
      "/home/${username}/.local/share/docker/volumes/uptime-kuma_kuma_data/_data"
      "/home/${username}/.local/share/docker/volumes/unifi_unifi_app_config/_data"
      "/home/${username}/.local/share/docker/volumes/n8n_n8n_data/_data"
      "/home/${username}/.local/share/docker/volumes/plane_plane_uploads/_data"
      "/var/lib/headscale"
      "/var/lib/vaultwarden"
      "/etc/secrets"
    ];
    excludes = [
      "*.log" "*.tmp" "*.cache"
      # SQLite WAL files — backed up via safe dump in preScript
      "*/finance/data/vaultkeeper.db-wal"
      "*/finance/data/vaultkeeper.db-shm"
      # Calibre Web thumbnail cache (~11G, regenerable from library)
      "*/calibre/data/config/thumbnails/*"
    ];
    tags = [ "services" "docker" "headscale" "vaultwarden" "openclaw" "unifi" "n8n" "plane" ];
    schedule = "*-*-* 19:30:00";
    retentionDays = 30;
    retentionPolicy = "--keep-monthly 3";
    preScript = ''
      # Safe SQLite dump of Vaultkeeper finance DB (avoids backing up locked WAL)
      VAULTKEEPER_DB="/home/${username}/.openclaw/workspace/finance/data/vaultkeeper.db"
      if [ -f "$VAULTKEEPER_DB" ]; then
        log "Dumping Vaultkeeper SQLite database..."
        ${pkgs.sqlite}/bin/sqlite3 "$VAULTKEEPER_DB" ".backup /home/${username}/.openclaw/workspace/finance/data/vaultkeeper-backup.db" 2>&1 || log "WARNING: Vaultkeeper DB dump failed (non-fatal)"
      fi
    '';
    description = "Docker configs, Headscale state, secrets, Vaultwarden, Uptime Kuma, OpenClaw, UniFi, n8n, Plane";
  };

  # Large media libraries — weekly Sunday after nextcloud
  librariesBackup = mkResticBackup {
    name = "libraries";
    passwordFile = "/etc/secrets/restic-services";
    repoSuffix = "services.restic";
    backupPaths = [
      "/home/${username}/romm-library"
      "/home/${username}/calibre-library"
    ];
    excludes = [ "*.log" "*.tmp" "*.cache" ];
    tags = [ "libraries" "romm" "calibre" ];
    schedule = "Sun *-*-* 20:30:00";
    retentionDays = 30;
    retentionPolicy = "--keep-monthly 3";
    description = "RomM ROMs + Calibre book library (~260GB)";
  };

  nextcloudBackup = mkResticBackup {
    name = "nextcloud";
    passwordFile = "/etc/secrets/restic-nextcloud";
    repoSuffix = "nextcloud.restic";
    backupPaths = [ "/var/lib/nextcloud-data" ];
    excludes = [
      "*.log" "*.part" "upload_tmp/*"
      # Nextcloud app code (regenerated from Docker image / app store).
      # IMPORTANT: anchor each pattern to the source root with the
      # /var/lib/nextcloud-data/ prefix. A naked "*/lib/*" pattern matches
      # /var/lib/ANYTHING because restic glob `*` doesn't cross `/`, so
      # "*/lib/*" matches the 3-segment path /var/lib/nextcloud-data itself
      # — excluding the entire source. (AINF triage 2026-05-14: this caused
      # all nextcloud backups to be 0 B for months.)
      "/var/lib/nextcloud-data/3rdparty/*"
      "/var/lib/nextcloud-data/apps/*"
      "/var/lib/nextcloud-data/core/*"
      "/var/lib/nextcloud-data/dist/*"
      "/var/lib/nextcloud-data/lib/*"
      "/var/lib/nextcloud-data/themes/*"
      "/var/lib/nextcloud-data/vendor-bin/*"
      # Nextcloud data caches and regenerable content (these patterns are
      # already unambiguous because no parent of the source contains them,
      # but anchored for consistency).
      "/var/lib/nextcloud-data/data/*/files_trashbin/*"
      "/var/lib/nextcloud-data/data/*/files_versions/*"
      "/var/lib/nextcloud-data/data/appdata_*/preview/*"
      "/var/lib/nextcloud-data/data/*/cache/*"
    ];
    tags = [ "nextcloud" ];
    schedule = "Sun *-*-* 20:00:00";
    retentionDays = 14;
    retentionPolicy = "--keep-monthly 2";
    description = "Nextcloud user data + config";
  };

in lib.mkIf (systemSettings.vpsResticBackupEnable or false) {
  # Backup services
  systemd.services.vps-restic-databases = databasesBackup.service;
  systemd.services.vps-restic-services = servicesBackup.service;
  systemd.services.vps-restic-libraries = librariesBackup.service;
  systemd.services.vps-restic-nextcloud = nextcloudBackup.service;

  # Backup timers
  systemd.timers.vps-restic-databases = databasesBackup.timer;
  systemd.timers.vps-restic-services = servicesBackup.timer;
  systemd.timers.vps-restic-libraries = librariesBackup.timer;
  systemd.timers.vps-restic-nextcloud = nextcloudBackup.timer;

  # Declarative ACL grant on /var/lib/nextcloud-data so the non-root
  # akunito-owned restic backup can read it. Idempotent; runs at boot and
  # before each nextcloud backup. If the Nextcloud Docker container is
  # ever recreated and resets ownership/perms, this re-applies the grant.
  # See known-issues.md for the full root-cause context.
  systemd.services.vps-backup-source-acls = {
    description = "Apply POSIX ACLs to backup source paths (idempotent)";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    before = [ "vps-restic-nextcloud.service" ];
    path = [ pkgs.acl pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "vps-backup-source-acls" ''
        set -uo pipefail
        for dir in /var/lib/nextcloud-data; do
          if [ -d "$dir" ]; then
            setfacl -R -m u:${username}:rX "$dir" 2>&1 || true
            setfacl -R -d -m u:${username}:rX "$dir" 2>&1 || true
            echo "ACL applied: $dir"
          else
            echo "Skipping (not present): $dir"
          fi
        done
      '';
    };
  };
}
