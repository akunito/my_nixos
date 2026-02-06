# Database Backup Module
#
# Configures automated backups for PostgreSQL and MariaDB databases.
# Creates timestamped dumps that can be easily restored.
#
# Features:
# - Daily pg_dump for PostgreSQL databases
# - Daily mysqldump for MariaDB databases
# - Automatic cleanup of old backups
# - Prometheus metrics for backup monitoring
#
# Configuration via systemSettings:
# - postgresqlBackupEnable: Enable PostgreSQL backups
# - mariadbBackupEnable: Enable MariaDB backups
# - databaseBackupLocation: Backup directory (default: /var/backup/databases)
# - databaseBackupStartAt: Systemd OnCalendar schedule (default: daily at 2 AM)
# - databaseBackupRetainDays: Days to retain backups (default: 7)

{ pkgs, lib, systemSettings, config, ... }:

let
  cfg = {
    postgresqlEnable = systemSettings.postgresqlBackupEnable or false;
    mariadbEnable = systemSettings.mariadbBackupEnable or false;
    location = systemSettings.databaseBackupLocation or "/var/backup/databases";
    startAt = systemSettings.databaseBackupStartAt or "*-*-* 02:00:00";
    retainDays = systemSettings.databaseBackupRetainDays or 7;
  };

  pgPort = systemSettings.postgresqlServerPort or 5432;
  pgDatabases = systemSettings.postgresqlServerDatabases or [];

  mariaPort = systemSettings.mariadbServerPort or 3306;
  mariaDatabases = systemSettings.mariadbServerDatabases or [];

  # Script to backup all PostgreSQL databases
  postgresqlBackupScript = pkgs.writeShellScript "postgresql-backup" ''
    set -euo pipefail

    BACKUP_DIR="${cfg.location}/postgresql"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETAIN_DAYS=${toString cfg.retainDays}

    mkdir -p "$BACKUP_DIR"

    echo "Starting PostgreSQL backup at $(date)"

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

    # Cleanup old backups
    echo "Cleaning up backups older than $RETAIN_DAYS days"
    find "$BACKUP_DIR" -name "*.dump" -mtime +$RETAIN_DAYS -delete
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETAIN_DAYS -delete

    # Write metrics for Prometheus
    METRICS_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$METRICS_DIR" ]; then
      cat > "$METRICS_DIR/postgresql_backup.prom.tmp" << EOF
    # HELP postgresql_backup_last_success_timestamp Last successful backup timestamp
    # TYPE postgresql_backup_last_success_timestamp gauge
    postgresql_backup_last_success_timestamp $(date +%s)
    # HELP postgresql_backup_status Backup status (1=success, 0=failed)
    # TYPE postgresql_backup_status gauge
    postgresql_backup_status 1
    EOF
      mv "$METRICS_DIR/postgresql_backup.prom.tmp" "$METRICS_DIR/postgresql_backup.prom"
    fi

    echo "PostgreSQL backup completed at $(date)"
  '';

  # Script to backup all MariaDB databases
  mariadbBackupScript = pkgs.writeShellScript "mariadb-backup" ''
    set -euo pipefail

    BACKUP_DIR="${cfg.location}/mariadb"
    DATE=$(date +%Y%m%d_%H%M%S)
    RETAIN_DAYS=${toString cfg.retainDays}

    mkdir -p "$BACKUP_DIR"

    echo "Starting MariaDB backup at $(date)"

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

    # Cleanup old backups
    echo "Cleaning up backups older than $RETAIN_DAYS days"
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +$RETAIN_DAYS -delete

    # Write metrics for Prometheus
    METRICS_DIR="/var/lib/prometheus-node-exporter/textfile"
    if [ -d "$METRICS_DIR" ]; then
      cat > "$METRICS_DIR/mariadb_backup.prom.tmp" << EOF
    # HELP mariadb_backup_last_success_timestamp Last successful backup timestamp
    # TYPE mariadb_backup_last_success_timestamp gauge
    mariadb_backup_last_success_timestamp $(date +%s)
    # HELP mariadb_backup_status Backup status (1=success, 0=failed)
    # TYPE mariadb_backup_status gauge
    mariadb_backup_status 1
    EOF
      mv "$METRICS_DIR/mariadb_backup.prom.tmp" "$METRICS_DIR/mariadb_backup.prom"
    fi

    echo "MariaDB backup completed at $(date)"
  '';

in
lib.mkMerge [
  # PostgreSQL backup service
  (lib.mkIf cfg.postgresqlEnable {
    systemd.services.postgresql-backup = {
      description = "PostgreSQL Database Backup";
      after = [ "postgresql.service" ];
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
      description = "PostgreSQL Database Backup Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    # Create backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.location}/postgresql 0750 root root -"
    ];
  })

  # MariaDB backup service
  (lib.mkIf cfg.mariadbEnable {
    systemd.services.mariadb-backup = {
      description = "MariaDB Database Backup";
      after = [ "mysql.service" ];
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
      description = "MariaDB Database Backup Timer";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.startAt;
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

    # Create backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.location}/mariadb 0750 root root -"
    ];
  })

  # Create Prometheus textfile directory if any backup is enabled
  (lib.mkIf (cfg.postgresqlEnable || cfg.mariadbEnable) {
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus-node-exporter/textfile 0775 root wheel -"
    ];
  })
]
