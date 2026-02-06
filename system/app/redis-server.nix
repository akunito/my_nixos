# Redis Server Module
#
# Configures a centralized Redis server for caching and session storage.
# Designed for LXC_database container to serve Plane, Nextcloud, and other apps.
#
# Features:
# - Password authentication
# - Numbered databases (db0=Plane, db1=Nextcloud, db2=LiftCraft, etc.)
# - Memory limits with LRU eviction
# - Prometheus redis_exporter integration
#
# Database numbering convention:
# - db0: Plane (project management)
# - db1: Nextcloud (session cache)
# - db2: LiftCraft (Rails cache)
# - db3+: Future services
#
# Configuration via systemSettings:
# - redisServerEnable: Enable Redis server
# - redisServerPort: Server port (default: 6379)
# - redisServerMaxMemory: Maximum memory (default: 1gb)
# - redisServerPasswordFile: Path to file containing password

{ pkgs, lib, systemSettings, config, ... }:

let
  cfg = {
    enable = systemSettings.redisServerEnable or false;
    port = systemSettings.redisServerPort or 6379;
    maxMemory = systemSettings.redisServerMaxMemory or "1gb";
    passwordFile = systemSettings.redisServerPasswordFile or "";
  };

in
lib.mkIf cfg.enable {
  # Use a named Redis instance for homelab (allows multiple instances if needed)
  services.redis.servers.homelab = {
    enable = true;
    port = cfg.port;

    # Bind to all interfaces for LAN access
    bind = "0.0.0.0";

    # Password authentication
    requirePassFile = if cfg.passwordFile != "" then cfg.passwordFile else null;

    # Memory configuration
    settings = {
      # Memory limit with LRU eviction for cache workloads
      maxmemory = cfg.maxMemory;
      maxmemory-policy = "allkeys-lru";

      # Persistence - RDB snapshots for durability
      save = [
        "900 1"   # Save after 900 sec if at least 1 key changed
        "300 10"  # Save after 300 sec if at least 10 keys changed
        "60 10000" # Save after 60 sec if at least 10000 keys changed
      ];

      # Number of databases (0-15 available, we use 0-3 for now)
      databases = 16;

      # Logging
      loglevel = "notice";

      # Security - disable dangerous commands
      rename-command = [
        "FLUSHALL" ""
        "FLUSHDB" ""
        "CONFIG" ""
        "DEBUG" ""
      ];

      # Performance
      tcp-keepalive = 300;
      timeout = 0;

      # Append-only file for better durability (optional, adds latency)
      # appendonly = "yes";
      # appendfsync = "everysec";
    };
  };

  # Prometheus redis_exporter for monitoring
  services.prometheus.exporters.redis = lib.mkIf (systemSettings.prometheusRedisExporterEnable or false) {
    enable = true;
    port = systemSettings.prometheusRedisExporterPort or 9121;
    extraFlags = [
      "--redis.addr=redis://127.0.0.1:${toString cfg.port}"
    ] ++ lib.optional (cfg.passwordFile != "") "--redis.password-file=${cfg.passwordFile}";
  };

  # Open firewall ports
  networking.firewall.allowedTCPPorts = [
    cfg.port
  ] ++ lib.optional (systemSettings.prometheusRedisExporterEnable or false)
    (systemSettings.prometheusRedisExporterPort or 9121);
}
