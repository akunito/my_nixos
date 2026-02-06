# Database Secrets Module
#
# Deploys database credentials from git-crypt encrypted secrets/domains.nix
# to /etc/secrets/ directory for use by PostgreSQL, MariaDB, Redis, and PgBouncer.
#
# This module reads passwords from the centralized secrets file and creates
# properly permissioned files that database services can read.
#
# Configuration via systemSettings:
# - postgresqlServerEnable: Creates PostgreSQL user password files
# - mariadbServerEnable: Creates MariaDB user password files
# - redisServerEnable: Creates Redis password file

{ pkgs, lib, systemSettings, config, ... }:

let
  secrets = import ../../secrets/domains.nix;

  # Check if any database service is enabled
  anyDatabaseEnabled = (systemSettings.postgresqlServerEnable or false)
                    || (systemSettings.mariadbServerEnable or false)
                    || (systemSettings.redisServerEnable or false);

in
lib.mkIf anyDatabaseEnabled {
  # Create /etc/secrets directory with proper permissions
  systemd.tmpfiles.rules = [
    "d /etc/secrets 0700 root root -"
  ];

  # Deploy PostgreSQL password files
  environment.etc = lib.mkMerge [
    # PostgreSQL passwords
    (lib.mkIf (systemSettings.postgresqlServerEnable or false) {
      "secrets/db-plane-password" = {
        text = secrets.dbPlanePassword;
        mode = "0440";
        user = "root";
        group = "postgres";
      };
      "secrets/db-liftcraft-password" = {
        text = secrets.dbLiftcraftPassword;
        mode = "0440";
        user = "root";
        group = "postgres";
      };
    })

    # MariaDB passwords
    (lib.mkIf (systemSettings.mariadbServerEnable or false) {
      "secrets/db-nextcloud-password" = {
        text = secrets.dbNextcloudPassword;
        mode = "0440";
        user = "root";
        group = "mysql";
      };
    })

    # Redis password
    (lib.mkIf (systemSettings.redisServerEnable or false) {
      "secrets/redis-password" = {
        text = secrets.redisServerPassword;
        mode = "0444";  # Redis exporter needs to read this
        user = "root";
        group = "root";
      };
    })
  ];
}
