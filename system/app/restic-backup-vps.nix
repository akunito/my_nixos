# VPS Restic Backup to TrueNAS via SFTP
#
# Automated backup of VPS data to TrueNAS via Tailscale SFTP.
# Four separate backup jobs with independent schedules and retention policies:
#   - databases:  PostgreSQL + MariaDB dumps (daily at 19:00, keep 30 days) → extpool
#   - services:   Docker configs, Headscale, Vaultwarden, secrets (daily at 19:30, keep 30 days) → extpool
#   - nextcloud:  Nextcloud data directory (weekly Sunday at 20:00, keep 14 days) → extpool
#   - libraries:  RomM ROMs + Calibre books ~260GB (weekly Sunday at 20:30, keep 30 days) → extpool
#   - immich:     Immich photo library ~92GB + DB dump (weekly Sunday at 21:00, keep 30 days) → extpool
#
# All VPS backups target extpool/vps-backups/ on TrueNAS.
#
# Schedule rationale: NAS sleeps 23:00-16:00. Backups run 19:00-22:00 window.
#
# Feature flag: vpsResticBackupEnable = true (in profile config)
#
# Prerequisites:
#   - SSH key at /home/<user>/.ssh/id_ed25519_restic (passwordless, for akunito on NAS)
#   - Password files at /etc/secrets/restic-{databases,services,nextcloud,immich}
#   - Restic repos initialized on TrueNAS:
#     - /mnt/extpool/vps-backups/databases.restic
#     - /mnt/extpool/vps-backups/services.restic
#     - /mnt/extpool/vps-backups/nextcloud.restic
#     - /mnt/extpool/vps-backups/immich.restic
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

      # Quiescent copy of the Minecraft world.
      #
      # Without this we back up region files while the server is mid-write, so
      # the snapshot is crash-consistent at best and a restore can carry corrupt
      # chunks. Restore from data/world-snapshot, not data/world.
      #
      # The copy runs INSIDE the container on purpose: data/world is owned by
      # the container uid (100999 on the host) and this service runs as
      # ${username}. restic can read it via CAP_DAC_READ_SEARCH on its wrapper,
      # but a plain cp here cannot. Doing it container-side sidesteps that.
      #
      # Every step is `|| true`-guarded so `set -e` can never skip save-on and
      # leave the live server with saving disabled.
      export DOCKER_HOST=unix:///run/user/1000/docker.sock
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -qw minecraft; then
        DOCKER=docker
        log "Minecraft is running - flushing world to disk before snapshot..."
        $DOCKER exec minecraft rcon-cli save-off      >/dev/null 2>&1 || log "WARNING: save-off failed"
        $DOCKER exec minecraft rcon-cli save-all flush >/dev/null 2>&1 || log "WARNING: save-all flush failed"
        sleep 3
        # Copy to .tmp then swap, so an interrupted run never leaves a
        # half-written snapshot as the thing we would restore from.
        $DOCKER exec minecraft sh -c 'rm -rf /data/world-snapshot.tmp && cp -a /data/world /data/world-snapshot.tmp && rm -rf /data/world-snapshot && mv /data/world-snapshot.tmp /data/world-snapshot' \
          >/dev/null 2>&1 && log "World snapshot refreshed" || log "WARNING: world snapshot copy failed (non-fatal)"
        $DOCKER exec minecraft rcon-cli save-on >/dev/null 2>&1 \
          && log "Saving re-enabled" \
          || log "CRITICAL: could not re-enable saving - run 'rcon-cli save-on' by hand"
      else
        # Server stopped: data/world on disk is already quiescent, so the live
        # copy in this snapshot is itself a valid restore point.
        log "Minecraft not running - live world is already consistent, skipping flush"
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

  # Immich photo library — full library incl. generated thumbnails + ML data,
  # plus a logical dump of the containerized VectorChord Postgres. Weekly
  # Sunday 21:00 (after libraries 20:30, before NAS sleep 23:00). The first
  # snapshot (~92GB) may exceed the window at the 50 MB/s throttle — seed it
  # manually once during a long NAS-awake window; incrementals are small.
  immichBackup = mkResticBackup {
    name = "immich";
    passwordFile = "/etc/secrets/restic-immich";
    repoSuffix = "immich.restic";
    backupPaths = [
      "/home/${username}/immich-library"
      "/home/${username}/.backups/immich"
    ];
    excludes = [ "*.tmp" "*.part" ];
    tags = [ "immich" "photos" ];
    schedule = "Sun *-*-* 21:00:00";
    retentionDays = 30;
    retentionPolicy = "--keep-monthly 3";
    preScript = ''
      # Logical dump of the containerized Immich Postgres so the DB is captured
      # consistently in the same snapshot as the library. Uses the rootless
      # Docker socket; docker is on the service PATH (/run/current-system/sw/bin).
      export DOCKER_HOST="unix:///run/user/1000/docker.sock"
      DUMP_DIR="/home/${username}/.backups/immich"
      mkdir -p "$DUMP_DIR"
      if docker ps --format '{{.Names}}' | grep -qx immich_postgres; then
        log "Dumping Immich Postgres (pg_dumpall)..."
        docker exec immich_postgres pg_dumpall --username=postgres \
          > "$DUMP_DIR/immich-dumpall.sql" 2>>"$DUMP_DIR/dump.log" \
          || log "WARNING: Immich DB dump failed (non-fatal)"
      else
        log "WARNING: immich_postgres not running — skipping DB dump"
      fi
    '';
    description = "Immich photo library (~92GB incl. cache) + Postgres dump";
  };

in lib.mkIf (systemSettings.vpsResticBackupEnable or false) {
  # Deploy restic repository passwords declaratively to /etc/secrets so they
  # survive reboots and redeploys. These were previously placed by hand and
  # silently vanished, which broke the scheduled backups (e.g. nextcloud,
  # 2026-07 — "Resolving password failed: does not exist"). Values come from
  # git-crypt secrets/domains.nix via the profile's systemSettings. Owned
  # root:root 0600 — the non-root (akunito) backup service reads them through
  # the CAP_DAC_READ_SEARCH restic wrapper (same as the source files).
  environment.etc = lib.mkMerge [
    (lib.mkIf ((systemSettings.resticDatabasesPassword or "") != "") {
      "secrets/restic-databases" = {
        text = systemSettings.resticDatabasesPassword;
        mode = "0600"; user = "root"; group = "root";
      };
    })
    (lib.mkIf ((systemSettings.resticServicesPassword or "") != "") {
      "secrets/restic-services" = {
        text = systemSettings.resticServicesPassword;
        mode = "0600"; user = "root"; group = "root";
      };
    })
    (lib.mkIf ((systemSettings.resticNextcloudPassword or "") != "") {
      "secrets/restic-nextcloud" = {
        text = systemSettings.resticNextcloudPassword;
        mode = "0600"; user = "root"; group = "root";
      };
    })
    (lib.mkIf ((systemSettings.resticImmichPassword or "") != "") {
      "secrets/restic-immich" = {
        text = systemSettings.resticImmichPassword;
        mode = "0600"; user = "root"; group = "root";
      };
    })
  ];

  # Backup services
  systemd.services.vps-restic-databases = databasesBackup.service;
  systemd.services.vps-restic-services = servicesBackup.service;
  systemd.services.vps-restic-libraries = librariesBackup.service;
  systemd.services.vps-restic-nextcloud = nextcloudBackup.service;
  systemd.services.vps-restic-immich = immichBackup.service;

  # Backup timers
  systemd.timers.vps-restic-databases = databasesBackup.timer;
  systemd.timers.vps-restic-services = servicesBackup.timer;
  systemd.timers.vps-restic-libraries = librariesBackup.timer;
  systemd.timers.vps-restic-nextcloud = nextcloudBackup.timer;
  systemd.timers.vps-restic-immich = immichBackup.timer;

  # Let ${username} trigger the services backup without sudo, so
  # akucraft-backup-now can push offsite itself. Scoped to exactly that one
  # unit — not blanket systemd control.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "vps-restic-services.service" &&
          subject.user == "${username}") {
        return polkit.Result.YES;
      }
    });
  '';

  # AkuCraft operator tooling.
  #
  # Both scripts live here rather than in ~/.homelab so they inherit the repo
  # path, the sftp command and the ssh key from this module instead of
  # duplicating them in a shell script that would then drift.
  environment.systemPackages = [

    # akucraft-backup-now — pre-deployment snapshot.
    #
    # LOCAL FIRST, deliberately: the NAS sleeps roughly 23:00-16:00, so an
    # offsite-only pre-deploy backup is unusable for most of the day. This
    # always produces a local restore point in seconds, then pushes offsite
    # only if the NAS answers.
    (pkgs.writeShellScriptBin "akucraft-backup-now" ''
      set -uo pipefail
      export DOCKER_HOST=unix:///run/user/1000/docker.sock
      STAMP=$(date +%Y%m%d-%H%M%S)
      DEST="/home/${username}/.homelab/backups/akucraft/$STAMP"
      log() { echo "$(date -Iseconds) [akucraft-backup-now] $*"; }

      mkdir -p "$DEST"
      COPY_OK=0
      if docker ps --format '{{.Names}}' 2>/dev/null | grep -qw minecraft; then
        log "Flushing world (server is running)..."
        docker exec minecraft rcon-cli save-off       >/dev/null 2>&1 || log "WARNING: save-off failed"
        docker exec minecraft rcon-cli save-all flush >/dev/null 2>&1 || log "WARNING: flush failed"
        sleep 3
        docker cp minecraft:/data/world "$DEST/world" >/dev/null 2>&1 \
          && { COPY_OK=1; log "World copied to $DEST/world"; } \
          || log "ERROR: world copy FAILED - do not deploy"
        docker exec minecraft rcon-cli save-on >/dev/null 2>&1 \
          && log "Saving re-enabled" \
          || log "CRITICAL: could not re-enable saving - run 'rcon-cli save-on' by hand"
      else
        # The world belongs to uid 100999 inside the rootless userns, and
        # level.dat, playerdata/ and skinrestorer/ are not world-readable, so a
        # plain host-side cp silently produced a snapshot with no level.dat and
        # no player inventories (caught 2026-08-16). Copy through a throwaway
        # container, which runs as that uid and can read everything.
        log "Server stopped - copying the world through a container"
        docker run --rm \
          -v /home/${username}/.homelab/minecraft/data:/src:ro \
          -v "$DEST":/dst alpine \
          sh -c 'cp -a /src/world /dst/world' >/dev/null 2>&1 \
          && { COPY_OK=1; log "World copied to $DEST/world"; } \
          || log "ERROR: world copy FAILED - do not deploy"
      fi

      # A snapshot missing level.dat or playerdata is worse than no snapshot,
      # because it looks like one. Check rather than assume.
      for required in level.dat playerdata region; do
        [ -e "$DEST/world/$required" ] || { COPY_OK=0; log "ERROR: snapshot has no world/$required"; }
      done

      # Compose files and mod pins, so a rollback can rebuild the exact stack
      cp -a /home/${username}/.homelab/minecraft/docker-compose.yml "$DEST/" 2>/dev/null || true

      du -sh "$DEST" 2>/dev/null | sed 's/^/  size: /'
      log "Local snapshot ready: $DEST"

      # Prune to the last 10 local snapshots (292M each)
      ls -1dt /home/${username}/.homelab/backups/akucraft/*/ 2>/dev/null \
        | tail -n +11 | xargs -r rm -rf

      if [ "$COPY_OK" != "1" ]; then
        log "REFUSING to push a snapshot that failed verification. Fix it first."
        exit 1
      fi

      if timeout 8 ping -c1 -W3 ${target} >/dev/null 2>&1; then
        log "NAS is awake - pushing offsite too"
        systemctl start vps-restic-services.service \
          && log "Offsite backup complete" \
          || log "WARNING: offsite backup failed - local snapshot is still valid"
      else
        log "NAS asleep - local snapshot only (this is expected outside 16:00-23:00)"
      fi
      log "To roll back: stop the server, replace data/world with $DEST/world, start"
    '')

    # akucraft-restore-drill — prove the offsite repo actually restores.
    # Restores into a scratch directory only; never touches the live world.
    (pkgs.writeShellScriptBin "akucraft-restore-drill" ''
      set -uo pipefail
      export RESTIC_PASSWORD_FILE="/etc/secrets/restic-services"
      RESTIC="/run/wrappers/bin/restic"
      REPO="${repoBase}/services.restic"
      SFTP_CMD="${sftpCommand}"
      DEST="''${1:-/home/${username}/.homelab/backups/restore-drill}"
      log() { echo "$(date -Iseconds) [restore-drill] $*"; }

      if ! timeout 8 ping -c1 -W3 ${target} >/dev/null 2>&1; then
        log "NAS unreachable - it sleeps outside 16:00-23:00. Aborting."; exit 1
      fi

      rm -rf "$DEST"; mkdir -p "$DEST"
      log "Restoring the world snapshot from the latest offsite backup..."
      $RESTIC -r "$REPO" -o "sftp.command=$SFTP_CMD" restore latest \
        --target "$DEST" \
        --include /home/${username}/.homelab/minecraft/data/world-snapshot 2>&1 | tail -5

      W="$DEST/home/${username}/.homelab/minecraft/data/world-snapshot"
      if [ ! -d "$W" ]; then log "FAIL: world-snapshot not present in the restore"; exit 1; fi
      log "Restored to $W"
      du -sh "$W" | sed 's/^/  size: /'
      for f in level.dat region playerdata; do
        [ -e "$W/$f" ] && log "  OK   $f" || log "  MISSING $f"
      done
      log "Claim data (Flan) in the restore:"
      ls -1 "$W/data/claims" 2>/dev/null | sed 's/^/    /' || log "    none found"
      log "Drill complete. Boot it in a scratch container to fully verify."
    '')
  ];

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
