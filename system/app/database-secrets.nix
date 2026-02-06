# Database Secrets Module
#
# Deploys database credentials from systemSettings to /etc/secrets/ directory
# for use by PostgreSQL, MariaDB, Redis, and PgBouncer.
#
# Secrets are passed through systemSettings (loaded from git-crypt encrypted
# secrets/domains.nix in the profile config).
#
# Configuration via systemSettings:
# - postgresqlServerEnable: Creates PostgreSQL user password files
# - mariadbServerEnable: Creates MariaDB user password files
# - redisServerEnable: Creates Redis password file
# - dbPlanePassword, dbLiftcraftPassword: PostgreSQL passwords
# - dbNextcloudPassword: MariaDB password
# - redisServerPassword: Redis password

{ pkgs, lib, systemSettings, config, ... }:

let
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
    (lib.mkIf ((systemSettings.postgresqlServerEnable or false) && (systemSettings.dbPlanePassword or "") != "") {
      "secrets/db-plane-password" = {
        text = systemSettings.dbPlanePassword;
        mode = "0440";
        user = "root";
        group = "postgres";
      };
    })

    (lib.mkIf ((systemSettings.postgresqlServerEnable or false) && (systemSettings.dbLiftcraftPassword or "") != "") {
      "secrets/db-liftcraft-password" = {
        text = systemSettings.dbLiftcraftPassword;
        mode = "0440";
        user = "root";
        group = "postgres";
      };
    })

    # MariaDB passwords
    (lib.mkIf ((systemSettings.mariadbServerEnable or false) && (systemSettings.dbNextcloudPassword or "") != "") {
      "secrets/db-nextcloud-password" = {
        text = systemSettings.dbNextcloudPassword;
        mode = "0440";
        user = "root";
        group = "mysql";
      };
    })

    # Redis password
    (lib.mkIf ((systemSettings.redisServerEnable or false) && (systemSettings.redisServerPassword or "") != "") {
      "secrets/redis-password" = {
        text = systemSettings.redisServerPassword;
        mode = "0444";  # Redis exporter needs to read this
        user = "root";
        group = "root";
      };
    })
  ];
}
