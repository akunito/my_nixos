# MariaDB Server Module
#
# Configures a centralized MariaDB server for hosting databases.
# Designed for LXC_database container to serve Nextcloud and other apps.
#
# Features:
# - MariaDB server with secure defaults
# - Multiple database/user creation
# - Network authentication for LAN clients
# - Prometheus mysqld_exporter integration
#
# Configuration via systemSettings:
# - mariadbServerEnable: Enable the MariaDB server
# - mariadbServerPort: Server port (default: 3306)
# - mariadbServerDatabases: List of database names to create
# - mariadbServerUsers: List of { name, passwordFile, privileges } records

{ pkgs, lib, systemSettings, config, ... }:

let
  cfg = {
    enable = systemSettings.mariadbServerEnable or false;
    port = systemSettings.mariadbServerPort or 3306;
    databases = systemSettings.mariadbServerDatabases or [];
    users = systemSettings.mariadbServerUsers or [];
  };

  # Build ensureDatabases list
  ensureDatabases = cfg.databases;

  # Build ensureUsers list from user configs
  # Format: { name, ensurePermissions }
  ensureUsers = map (user: {
    name = user.name;
    ensurePermissions = user.privileges or {
      "${user.database or "*"}.*" = "ALL PRIVILEGES";
    };
  }) cfg.users;

  # Grant monitoring permissions to mysql user for the exporter (uses socket auth)
  # The exporter runs as OS user 'mysql' and connects via unix socket
  exporterUser = lib.optional (systemSettings.prometheusMariadbExporterEnable or false) {
    name = "mysql";
    ensurePermissions = {
      "*.*" = "PROCESS, REPLICATION CLIENT, SELECT";
    };
  };

in
lib.mkIf cfg.enable {
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;

    # Create databases
    ensureDatabases = ensureDatabases;

    # Create users (including exporter user if monitoring enabled)
    ensureUsers = ensureUsers ++ exporterUser;

    # MariaDB configuration
    settings = {
      mysqld = {
        # Network settings - bind to all interfaces for LAN access
        bind-address = "0.0.0.0";
        port = cfg.port;

        # Performance tuning
        innodb_buffer_pool_size = "1G";
        innodb_log_file_size = "256M";
        innodb_flush_log_at_trx_commit = 2;
        innodb_flush_method = "O_DIRECT";

        # Connection settings
        max_connections = 200;
        wait_timeout = 600;
        interactive_timeout = 600;

        # Query cache (disabled in MariaDB 10.1.7+, but explicit is good)
        query_cache_type = 0;
        query_cache_size = 0;

        # Character set
        character-set-server = "utf8mb4";
        collation-server = "utf8mb4_unicode_ci";

        # Logging
        slow_query_log = true;
        slow_query_log_file = "/var/log/mysql/slow.log";
        long_query_time = 2;

        # Security
        skip-name-resolve = true;
      };

      # Client defaults
      client = {
        default-character-set = "utf8mb4";
      };
    };
  };

  # Create log directory
  systemd.tmpfiles.rules = [
    "d /var/log/mysql 0750 mysql mysql -"
  ];

  # Set user passwords via postStart
  # MariaDB ensureUsers doesn't set passwords, so we handle it here
  systemd.services.mysql.postStart = let
    # Generate SQL to set passwords and grant remote access
    setPasswordSQL = lib.concatMapStrings (user:
      if user ? passwordFile && user.passwordFile != "" then ''
        password=$(cat "${user.passwordFile}")
        # Create user for remote access from LAN if not exists
        ${pkgs.mariadb}/bin/mysql -e "CREATE USER IF NOT EXISTS '${user.name}'@'192.168.8.%' IDENTIFIED BY '$password';"
        ${pkgs.mariadb}/bin/mysql -e "ALTER USER '${user.name}'@'192.168.8.%' IDENTIFIED BY '$password';"
        # Grant privileges
        ${pkgs.mariadb}/bin/mysql -e "GRANT ALL PRIVILEGES ON ${user.database or "*"}.* TO '${user.name}'@'192.168.8.%';"
        # Also handle localhost
        ${pkgs.mariadb}/bin/mysql -e "ALTER USER IF EXISTS '${user.name}'@'localhost' IDENTIFIED BY '$password';"
        ${pkgs.mariadb}/bin/mysql -e "FLUSH PRIVILEGES;"
      '' else ""
    ) cfg.users;
  in lib.mkAfter ''
    ${setPasswordSQL}
  '';

  # Prometheus mysqld_exporter config file for socket authentication
  # Uses mysql OS user via unix socket (OS user must match MySQL user)
  environment.etc."prometheus-mysqld-exporter.cnf" = lib.mkIf (systemSettings.prometheusMariadbExporterEnable or false) {
    text = ''
      [client]
      user = mysql
      socket = /run/mysqld/mysqld.sock
    '';
    mode = "0440";
    user = "mysql";
    group = "mysql";
  };

  # Prometheus mysqld_exporter for monitoring
  services.prometheus.exporters.mysqld = lib.mkIf (systemSettings.prometheusMariadbExporterEnable or false) {
    enable = true;
    port = systemSettings.prometheusMariadbExporterPort or 9104;
    # Run as mysql user for socket authentication
    runAsLocalSuperUser = true;
    # Config file with socket connection settings
    configFile = "/etc/prometheus-mysqld-exporter.cnf";
    # Enable per-database metrics collectors
    extraFlags = [
      "--collect.info_schema.tables"
      "--collect.info_schema.innodb_tablespaces"
      "--collect.info_schema.processlist"
    ];
  };

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    cfg.port
  ] ++ lib.optional (systemSettings.prometheusMariadbExporterEnable or false)
    (systemSettings.prometheusMariadbExporterPort or 9104);
}
