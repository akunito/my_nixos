# PostgreSQL Server Module
#
# Configures a centralized PostgreSQL server for hosting multiple databases.
# Designed for LXC_database container to serve Plane, LiftCraft, and other apps.
#
# Features:
# - PostgreSQL 17 (or configurable version)
# - Multiple database/user creation
# - Network authentication for LAN clients
# - Prometheus postgres_exporter integration
#
# Configuration via systemSettings:
# - postgresqlServerEnable: Enable the PostgreSQL server
# - postgresqlServerPort: Server port (default: 5432)
# - postgresqlServerPackage: PostgreSQL package (default: postgresql_17)
# - postgresqlServerDatabases: List of databases to create
# - postgresqlServerUsers: List of { name, passwordFile, ensureDBOwnership } records
# - postgresqlServerAuthentication: Extra pg_hba.conf entries

{ pkgs, lib, systemSettings, config, ... }:

let
  cfg = {
    enable = systemSettings.postgresqlServerEnable or false;
    port = systemSettings.postgresqlServerPort or 5432;
    package = systemSettings.postgresqlServerPackage or pkgs.postgresql_17;
    databases = systemSettings.postgresqlServerDatabases or [];
    users = systemSettings.postgresqlServerUsers or [];
    extraAuth = systemSettings.postgresqlServerAuthentication or "";
  };

  # Build ensureDatabases list
  ensureDatabases = cfg.databases;

  # Build ensureUsers list from user configs
  ensureUsers = map (user: {
    name = user.name;
    ensureDBOwnership = user.ensureDBOwnership or true;
  }) cfg.users;

in
lib.mkIf cfg.enable {
  services.postgresql = {
    enable = true;
    package = cfg.package;
    port = cfg.port;

    # Listen on all interfaces for LAN access
    enableTCPIP = true;

    # Create databases
    ensureDatabases = ensureDatabases;

    # Create users
    ensureUsers = ensureUsers;

    # PostgreSQL configuration
    settings = {
      # Performance tuning for centralized database server
      shared_buffers = "2GB";
      effective_cache_size = "6GB";
      maintenance_work_mem = "512MB";
      work_mem = "64MB";

      # WAL settings
      wal_buffers = "64MB";
      min_wal_size = "1GB";
      max_wal_size = "4GB";

      # Connection settings
      max_connections = 200;

      # Logging
      log_destination = "stderr";
      logging_collector = true;
      log_directory = "log";
      log_filename = "postgresql-%Y-%m-%d.log";
      log_rotation_age = "1d";
      log_rotation_size = "100MB";
      log_min_duration_statement = 1000; # Log queries taking > 1 second

      # Timezone
      timezone = systemSettings.timezone or "UTC";
    };

    # Authentication configuration
    # Allow password auth from LAN (192.168.8.0/24) and WireGuard tunnel (172.26.5.0/24)
    authentication = lib.mkForce ''
      # Local connections
      local   all             all                                     peer
      local   all             postgres                                peer

      # IPv4 localhost
      host    all             all             127.0.0.1/32            scram-sha-256

      # IPv6 localhost
      host    all             all             ::1/128                 scram-sha-256

      # LAN access (homelab network)
      host    all             all             192.168.8.0/24          scram-sha-256

      # WireGuard tunnel access
      host    all             all             172.26.5.0/24           scram-sha-256

      # Extra authentication rules from profile config
      ${cfg.extraAuth}
    '';
  };

  # Create password files and set user passwords via postStart
  # This is a workaround since NixOS postgresql module doesn't natively support password files
  systemd.services.postgresql.postStart = let
    # Generate SQL to set passwords for users with passwordFile defined
    setPasswordSQL = lib.concatMapStrings (user:
      if user ? passwordFile && user.passwordFile != "" then ''
        password=$(cat "${user.passwordFile}")
        $PSQL -c "ALTER USER \"${user.name}\" WITH PASSWORD '$password';"
      '' else ""
    ) cfg.users;
  in lib.mkAfter ''
    PSQL="psql --port=${toString cfg.port}"
    ${setPasswordSQL}
  '';

  # Prometheus postgres_exporter for monitoring
  services.prometheus.exporters.postgres = lib.mkIf (systemSettings.prometheusPostgresExporterEnable or false) {
    enable = true;
    port = systemSettings.prometheusPostgresExporterPort or 9187;
    runAsLocalSuperUser = true;
    dataSourceName = "user=postgres host=/run/postgresql dbname=postgres";
  };

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    cfg.port
  ] ++ lib.optional (systemSettings.prometheusPostgresExporterEnable or false)
    (systemSettings.prometheusPostgresExporterPort or 9187);
}
