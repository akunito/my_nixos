# PgBouncer Connection Pooler Module
#
# Configures PgBouncer for PostgreSQL connection pooling.
# Reduces connection overhead and improves performance for apps with many short-lived connections.
#
# Features:
# - Transaction pooling mode (default)
# - Authentication via userlist file
# - Configurable pool sizes
#
# Configuration via systemSettings:
# - pgBouncerEnable: Enable PgBouncer
# - pgBouncerPort: Listening port (default: 6432)
# - pgBouncerPoolMode: Pool mode - session, transaction, or statement (default: transaction)
# - pgBouncerMaxClientConn: Maximum client connections (default: 1000)
# - pgBouncerDefaultPoolSize: Default pool size per user/database (default: 20)

{ pkgs, lib, systemSettings, config, ... }:

let
  cfg = {
    enable = systemSettings.pgBouncerEnable or false;
    port = systemSettings.pgBouncerPort or 6432;
    poolMode = systemSettings.pgBouncerPoolMode or "transaction";
    maxClientConn = systemSettings.pgBouncerMaxClientConn or 1000;
    defaultPoolSize = systemSettings.pgBouncerDefaultPoolSize or 20;
  };

  # PostgreSQL settings for reference
  pgPort = systemSettings.postgresqlServerPort or 5432;
  pgUsers = systemSettings.postgresqlServerUsers or [];
  pgDatabases = systemSettings.postgresqlServerDatabases or [];

  # Build databases config - proxy all configured databases to local PostgreSQL
  databasesConfig = lib.concatMapStrings (db: ''
    ${db} = host=127.0.0.1 port=${toString pgPort} dbname=${db}
  '') pgDatabases;

  # Build userlist file content from PostgreSQL users
  # Format: "username" "password" or "username" "md5hash"
  # We'll use auth_query method to delegate authentication to PostgreSQL
  userlistContent = lib.concatMapStrings (user: ''
    "${user.name}" ""
  '') pgUsers;

in
lib.mkIf cfg.enable {
  services.pgbouncer = {
    enable = true;

    # Connection pooling settings
    settings = {
      # Database configuration - proxy to local PostgreSQL (moved from top-level)
      databases = lib.listToAttrs (map (db: {
        name = db;
        value = "host=127.0.0.1 port=${toString pgPort} dbname=${db}";
      }) pgDatabases);

      pgbouncer = {
        # Listen on all interfaces for LAN access (moved from top-level)
        listen_addr = "0.0.0.0";
        listen_port = cfg.port;

        # Pool mode: transaction is best for web apps
        pool_mode = cfg.poolMode;

        # Connection limits
        max_client_conn = cfg.maxClientConn;
        default_pool_size = cfg.defaultPoolSize;
        min_pool_size = 5;
        reserve_pool_size = 5;
        reserve_pool_timeout = 3;

        # Authentication - delegate to PostgreSQL via auth_query
        # This avoids maintaining a separate userlist with passwords
        auth_type = "scram-sha-256";
        auth_query = "SELECT usename, passwd FROM pg_shadow WHERE usename=$1";
        auth_user = "pgbouncer";

        # Logging
        log_connections = 1;
        log_disconnections = 1;
        log_pooler_errors = 1;

        # Admin access (for pgbouncer console)
        admin_users = "postgres";
        stats_users = "postgres";

        # Timeouts
        server_connect_timeout = 15;
        server_login_retry = 15;
        query_timeout = 0;
        query_wait_timeout = 120;
        client_idle_timeout = 0;
        server_idle_timeout = 600;

        # Security
        ignore_startup_parameters = "extra_float_digits";
      };
    };
  };

  # Create pgbouncer user in PostgreSQL for auth_query
  # This user needs SELECT on pg_shadow
  services.postgresql.ensureUsers = lib.mkIf (systemSettings.postgresqlServerEnable or false) [
    {
      name = "pgbouncer";
      ensureDBOwnership = false;
    }
  ];

  # Grant pgbouncer user access to pg_shadow for auth_query
  systemd.services.postgresql.postStart = lib.mkIf (systemSettings.postgresqlServerEnable or false) (lib.mkAfter ''
    PSQL="psql --port=${toString pgPort}"
    # Grant pgbouncer user permission to read pg_shadow for auth_query
    $PSQL -c "GRANT SELECT ON pg_shadow TO pgbouncer;" || true
  '');

  # Open firewall port
  networking.firewall.allowedTCPPorts = [ cfg.port ];
}
