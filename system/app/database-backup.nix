# Database Backup Module
#
# Configures automated backups for PostgreSQL and MariaDB databases.
# Creates timestamped dumps that can be easily restored.
#
# Features:
# - Daily pg_dump for PostgreSQL databases (custom + plain SQL formats)
# - Daily mysqldump for MariaDB databases
# - Hourly pg_dump for PostgreSQL (custom format only, count-based retention)
# - Hourly mysqldump for MariaDB (compressed, count-based retention)
# - Optional Redis BGSAVE trigger before backups for cache consistency
# - Automatic cleanup of old backups (time-based for daily, count-based for hourly)
# - Prometheus metrics for backup monitoring
#
# Configuration via systemSettings:
# - postgresqlBackupEnable: Enable PostgreSQL backups
# - mariadbBackupEnable: Enable MariaDB backups
# - databaseBackupLocation: Backup directory (default: /var/backup/databases)
# - databaseBackupStartAt: Systemd OnCalendar schedule (default: daily at 2 AM)
# - databaseBackupRetainDays: Days to retain daily backups (default: 7)
# - databaseBackupHourlyEnable: Enable hourly backups (default: false)
# - databaseBackupHourlySchedule: Hourly schedule (default: "*:00:00")
# - databaseBackupHourlyRetainCount: Hourly backups to retain (default: 72)
# - redisBgsaveBeforeBackup: Trigger Redis BGSAVE before backups (default: false)
# - redisBgsaveTimeout: Seconds to wait for BGSAVE (default: 60)

{ pkgs, lib, systemSettings, config, ... }:

let
  cfg = {
    postgresqlEnable = systemSettings.postgresqlBackupEnable or false;
    mariadbEnable = systemSettings.mariadbBackupEnable or false;
    location = systemSettings.databaseBackupLocation or "/var/backup/databases";
    startAt = systemSettings.databaseBackupStartAt or "*-*-* 02:00:00";
    retainDays = systemSettings.databaseBackupRetainDays or 7;
    # Hourly backup settings
    hourlyEnable = systemSettings.databaseBackupHourlyEnable or false;
    hourlySchedule = systemSettings.databaseBackupHourlySchedule or "*:00:00";
    hourlyRetainCount = systemSettings.databaseBackupHourlyRetainCount or 72;
    # Redis BGSAVE settings
    redisBgsave = systemSettings.redisBgsaveBeforeBackup or false;
    redisBgsaveTimeout = systemSettings.redisBgsaveTimeout or 60;
    redisPasswordFile = systemSettings.redisServerPasswordFile or "";
  };

  pgPort = systemSettings.postgresqlServerPort or 5432;
  pgDatabases = systemSettings.postgresqlServerDatabases or [];

  mariaPort = systemSettings.mariadbServerPort or 3306;
  mariaDatabases = systemSettings.mariadbServerDatabases or [];

  # Script to trigger Redis BGSAVE before backups
  redisBgsaveScript = pkgs.writeShellScript "redis-bgsave" ''
    set -euo pipefail

    echo "Triggering Redis BGSAVE at $(date)"

    # Read Redis password
    if [ -f "${cfg.redisPasswordFile}" ]; then
      REDIS_PASS=$(cat "${cfg.redisPasswordFile}")
    else
      echo "ERROR: Redis password file not found: ${cfg.redisPasswordFile}"
      exit 1
    fi

    # Get LASTSAVE timestamp before BGSAVE
    BEFORE=$(${pkgs.redis}/bin/redis-cli -a "$REDIS_PASS" --no-auth-warning LASTSAVE 2>/dev/null)
    echo "LASTSAVE before: $BEFORE"

    # Trigger BGSAVE
    ${pkgs.redis}/bin/redis-cli -a "$REDIS_PASS" --no-auth-warning BGSAVE 2>/dev/null
    echo "BGSAVE triggered"

    # Wait for completion
    TIMEOUT=${toString cfg.redisBgsaveTimeout}
    for i in $(seq 1 $TIMEOUT); do
      AFTER=$(${pkgs.redis}/bin/redis-cli -a "$REDIS_PASS" --no-auth-warning LASTSAVE 2>/dev/null)
      if [ "$AFTER" != "$BEFORE" ]; then
        echo "BGSAVE completed successfully (LASTSAVE: $AFTER)"
        exit 0
      fi
      sleep 1
    done

    echo "ERROR: BGSAVE timeout after $TIMEOUT seconds"
    exit 1
  '';

  # Script to backup all PostgreSQL databases (DAILY - both formats)
  postgresqlBackupScript = pkgs.writeShellScript "postgresql-backup-daily" ''
    set -euo pipefail

    BACKUP_DIR="${cfg.location}/postgresql/daily"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETAIN_DAYS=${toString cfg.retainDays}

    mkdir -p "$BACKUP_DIR"

    echo "Starting PostgreSQL DAILY backup at $(date)"

    # Backup each database
    ${lib.concatMapStrings (db: ''
      echo "Backing up database: ${db}"
      ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_17}/bin/pg_dump \
        --port=${toString pgPort} \
        --format=custom \
        --file="$BACKUP_DIR/${db}_$DATE.dump" \
        ${db}

      # Also create a plain SQL backup for easy inspection
      ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_17}/bin/pg_dump \
        --port=${toString pgPort} \
        --format=plain \
        --file="$BACKUP_DIR/${db}_$DATE.sql" \
        ${db}

      # Compress SQL backup
      ${pkgs.gzip}/bin/gzip -f "$BACKUP_DIR/${db}_$DATE.sql"

      echo "Completed backup of ${db}"
    '') pgDatabases}

    # Cleanup old backups (time-based)
    echo "Cleaning up daily backups older than $RETAIN_DAYS days"
    find "$BACKUP_DIR" -name "*.dump" -mtime +$RETAIN_DAYS -delete
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETAIN_DAYS -delete

    # Write metrics for Prometheus
    METRICS_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$METRICS_DIR" ]; then
      cat > "$METRICS_DIR/postgresql_backup_daily.prom.tmp" << EOF
# HELP postgresql_backup_daily_last_success_timestamp Last successful daily backup timestamp
# TYPE postgresql_backup_daily_last_success_timestamp gauge
postgresql_backup_daily_last_success_timestamp $(date +%s)
# HELP postgresql_backup_daily_status Daily backup status (1=success, 0=failed)
# TYPE postgresql_backup_daily_status gauge
postgresql_backup_daily_status 1
EOF
      mv "$METRICS_DIR/postgresql_backup_daily.prom.tmp" "$METRICS_DIR/postgresql_backup_daily.prom"
    fi

    echo "PostgreSQL DAILY backup completed at $(date)"
  '';

  # Script to backup all PostgreSQL databases (HOURLY - custom format only)
  postgresqlBackupHourlyScript = pkgs.writeShellScript "postgresql-backup-hourly" ''
    set -euo pipefail

    BACKUP_DIR="${cfg.location}/postgresql/hourly"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETAIN_COUNT=${toString cfg.hourlyRetainCount}

    mkdir -p "$BACKUP_DIR"

    echo "Starting PostgreSQL HOURLY backup at $(date)"

    # Backup each database (custom format only for speed)
    ${lib.concatMapStrings (db: ''
      echo "Backing up database: ${db}"
      ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_17}/bin/pg_dump \
        --port=${toString pgPort} \
        --format=custom \
        --file="$BACKUP_DIR/${db}_$DATE.dump" \
        ${db}

      echo "Completed hourly backup of ${db}"

      # Cleanup: keep only RETAIN_COUNT most recent backups per database
      echo "Cleaning up hourly backups for ${db} (keeping $RETAIN_COUNT most recent)"
      ls -1t "$BACKUP_DIR"/${db}_*.dump 2>/dev/null | tail -n +$((RETAIN_COUNT + 1)) | xargs -r rm -f
    '') pgDatabases}

    # Write metrics for Prometheus
    METRICS_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$METRICS_DIR" ]; then
      cat > "$METRICS_DIR/postgresql_backup_hourly.prom.tmp" << EOF
# HELP postgresql_backup_hourly_last_success_timestamp Last successful hourly backup timestamp
# TYPE postgresql_backup_hourly_last_success_timestamp gauge
postgresql_backup_hourly_last_success_timestamp $(date +%s)
# HELP postgresql_backup_hourly_status Hourly backup status (1=success, 0=failed)
# TYPE postgresql_backup_hourly_status gauge
postgresql_backup_hourly_status 1
EOF
      mv "$METRICS_DIR/postgresql_backup_hourly.prom.tmp" "$METRICS_DIR/postgresql_backup_hourly.prom"
    fi

    echo "PostgreSQL HOURLY backup completed at $(date)"
  '';

  # Script to backup all MariaDB databases (DAILY)
  mariadbBackupScript = pkgs.writeShellScript "mariadb-backup-daily" ''
    set -euo pipefail

    BACKUP_DIR="${cfg.location}/mariadb/daily"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETAIN_DAYS=${toString cfg.retainDays}

    mkdir -p "$BACKUP_DIR"

    echo "Starting MariaDB DAILY backup at $(date)"

    # Backup each database
    ${lib.concatMapStrings (db: ''
      echo "Backing up database: ${db}"
      ${pkgs.mariadb}/bin/mysqldump \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        ${db} > "$BACKUP_DIR/${db}_$DATE.sql"

      # Compress backup
      ${pkgs.gzip}/bin/gzip -f "$BACKUP_DIR/${db}_$DATE.sql"

      echo "Completed backup of ${db}"
    '') mariaDatabases}

    # Cleanup old backups (time-based)
    echo "Cleaning up daily backups older than $RETAIN_DAYS days"
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETAIN_DAYS -delete

    # Write metrics for Prometheus
    METRICS_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$METRICS_DIR" ]; then
      cat > "$METRICS_DIR/mariadb_backup_daily.prom.tmp" << EOF
# HELP mariadb_backup_daily_last_success_timestamp Last successful daily backup timestamp
# TYPE mariadb_backup_daily_last_success_timestamp gauge
mariadb_backup_daily_last_success_timestamp $(date +%s)
# HELP mariadb_backup_daily_status Daily backup status (1=success, 0=failed)
# TYPE mariadb_backup_daily_status gauge
mariadb_backup_daily_status 1
EOF
      mv "$METRICS_DIR/mariadb_backup_daily.prom.tmp" "$METRICS_DIR/mariadb_backup_daily.prom"
    fi

    echo "MariaDB DAILY backup completed at $(date)"
  '';

  # Script to backup all MariaDB databases (HOURLY)
  mariadbBackupHourlyScript = pkgs.writeShellScript "mariadb-backup-hourly" ''
    set -euo pipefail

    BACKUP_DIR="${cfg.location}/mariadb/hourly"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETAIN_COUNT=${toString cfg.hourlyRetainCount}

    mkdir -p "$BACKUP_DIR"

    echo "Starting MariaDB HOURLY backup at $(date)"

    # Backup each database
    ${lib.concatMapStrings (db: ''
      echo "Backing up database: ${db}"
      ${pkgs.mariadb}/bin/mysqldump \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        ${db} | ${pkgs.gzip}/bin/gzip > "$BACKUP_DIR/${db}_$DATE.sql.gz"

      echo "Completed hourly backup of ${db}"

      # Cleanup: keep only RETAIN_COUNT most recent backups per database
      echo "Cleaning up hourly backups for ${db} (keeping $RETAIN_COUNT most recent)"
      ls -1t "$BACKUP_DIR"/${db}_*.sql.gz 2>/dev/null | tail -n +$((RETAIN_COUNT + 1)) | xargs -r rm -f
    '') mariaDatabases}

    # Write metrics for Prometheus
    METRICS_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$METRICS_DIR" ]; then
      cat > "$METRICS_DIR/mariadb_backup_hourly.prom.tmp" << EOF
# HELP mariadb_backup_hourly_last_success_timestamp Last successful hourly backup timestamp
# TYPE mariadb_backup_hourly_last_success_timestamp gauge
mariadb_backup_hourly_last_success_timestamp $(date +%s)
# HELP mariadb_backup_hourly_status Hourly backup status (1=success, 0=failed)
# TYPE mariadb_backup_hourly_status gauge
mariadb_backup_hourly_status 1
EOF
      mv "$METRICS_DIR/mariadb_backup_hourly.prom.tmp" "$METRICS_DIR/mariadb_backup_hourly.prom"
    fi

    echo "MariaDB HOURLY backup completed at $(date)"
  '';

in
lib.mkMerge [
  # Redis BGSAVE service (runs before backups if enabled)
  (lib.mkIf cfg.redisBgsave {
    systemd.services.redis-pre-backup-bgsave = {
      description = "Trigger Redis BGSAVE before database backups";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = redisBgsaveScript;
        User = "root";
        Group = "root";
      };
    };
  })

  # PostgreSQL DAILY backup service
  (lib.mkIf cfg.postgresqlEnable {
    systemd.services.postgresql-backup = {
      description = "PostgreSQL Database Daily Backup";
      after = [ "postgresql.service" ] ++ lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      wants = lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      requires = [ "postgresql.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = postgresqlBackupScript;
        User = "root";
        Group = "root";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.location "/var/lib/prometheus-node-exporter" ];
      };
    };

    systemd.timers.postgresql-backup = {
      description = "PostgreSQL Database Daily Backup Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    # Create backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.location}/postgresql/daily 0750 root root -"
    ];
  })

  # PostgreSQL HOURLY backup service
  (lib.mkIf (cfg.postgresqlEnable && cfg.hourlyEnable) {
    systemd.services.postgresql-backup-hourly = {
      description = "PostgreSQL Database Hourly Backup";
      after = [ "postgresql.service" ] ++ lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      wants = lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      requires = [ "postgresql.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = postgresqlBackupHourlyScript;
        User = "root";
        Group = "root";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.location "/var/lib/prometheus-node-exporter" ];
      };
    };

    systemd.timers.postgresql-backup-hourly = {
      description = "PostgreSQL Database Hourly Backup Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.hourlySchedule;
        Persistent = true;
        RandomizedDelaySec = "2m";
      };
    };

    # Create hourly backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.location}/postgresql/hourly 0750 root root -"
    ];
  })

  # MariaDB DAILY backup service
  (lib.mkIf cfg.mariadbEnable {
    systemd.services.mariadb-backup = {
      description = "MariaDB Database Daily Backup";
      after = [ "mysql.service" ] ++ lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      wants = lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      requires = [ "mysql.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = mariadbBackupScript;
        User = "root";
        Group = "root";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.location "/var/lib/prometheus-node-exporter" ];
      };
    };

    systemd.timers.mariadb-backup = {
      description = "MariaDB Database Daily Backup Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    # Create backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.location}/mariadb/daily 0750 root root -"
    ];
  })

  # MariaDB HOURLY backup service
  (lib.mkIf (cfg.mariadbEnable && cfg.hourlyEnable) {
    systemd.services.mariadb-backup-hourly = {
      description = "MariaDB Database Hourly Backup";
      after = [ "mysql.service" ] ++ lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      wants = lib.optional cfg.redisBgsave "redis-pre-backup-bgsave.service";
      requires = [ "mysql.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = mariadbBackupHourlyScript;
        User = "root";
        Group = "root";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.location "/var/lib/prometheus-node-exporter" ];
      };
    };

    systemd.timers.mariadb-backup-hourly = {
      description = "MariaDB Database Hourly Backup Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.hourlySchedule;
        Persistent = true;
        RandomizedDelaySec = "2m";
      };
    };

    # Create hourly backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.location}/mariadb/hourly 0750 root root -"
    ];
  })

  # Create Prometheus textfile directory if any backup is enabled
  (lib.mkIf (cfg.postgresqlEnable || cfg.mariadbEnable) {
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
    ];
  })
]
