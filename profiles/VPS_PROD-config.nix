# VPS_PROD Profile Configuration
# Production VPS on Netcup RS 4000 G12 (Nuremberg)
#
# Extends VPS-base-config.nix
#
# Phase 1: Tailscale, Headscale, WireGuard (complete)
# Phase 2a: PostgreSQL, MariaDB, Redis, PgBouncer (complete — empty, ready to receive data)
# Phase 2b: Cloudflared tunnel (complete)
# Phase 2c: Email notifications via LXC_mailer (complete)
# Phase 2d: Grafana + Prometheus monitoring (complete)
# Phase 3a: Postfix relay + Docker infrastructure (complete)

let
  base = import ./VPS-base-config.nix;
  secrets = import ../secrets/domains.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "vps-prod";
    envProfile = "VPS_PROD";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles VPS_PROD -s -u -d";

    # System packages (extends base with database CLI tools)
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.postgresql_17
        pkgs.mariadb
        pkgs.redis
        pkgs.curl  # For healthchecks
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Tailscale (Phase 1 — first thing needed) ===
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${secrets.headscaleDomain}";
    tailscaleAcceptRoutes = true; # Accept routes from home subnet router
    tailscaleAcceptDns = true;

    # === Package Modules ===
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = false;

    # === System Services (ALL DISABLED — not needed on VPS) ===
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;

    # === VPN Services (Phase 1 — Headscale + WireGuard) ===
    headscaleEnable = true;
    headscaleDomain = secrets.headscaleDomain;
    headscalePort = 8080; # Internal; nginx terminates TLS on 443
    acmeEmail = secrets.acmeEmail; # For Let's Encrypt certificate

    wireguardServerEnable = true;
    wireguardServerPort = 51820;
    wireguardServerIp = "172.26.5.155/24";
    wireguardServerPrivateKeyFile = "/etc/secrets/wireguard/private.key";
    wireguardServerPeers = [
      {
        publicKey = secrets.pfsenseWireguardPubkey;
        presharedKeyFile = "/etc/secrets/wireguard/psk.key";
        allowedIPs = [ "192.168.8.0/24" "192.168.20.0/24" "172.26.5.1/32" ];
        persistentKeepalive = 25;
      }
    ];

    # === Docker subnet access for rootless Docker containers ===
    postgresqlServerAuthentication = ''
      host    all             all             10.0.0.0/8              scram-sha-256
      host    all             all             172.16.0.0/12           scram-sha-256
    '';

    # === Database Credentials (from git-crypt encrypted secrets/domains.nix) ===
    dbPlanePassword = secrets.dbPlanePassword;
    dbLiftcraftPassword = secrets.dbLiftcraftPassword;
    dbMatrixPassword = secrets.dbMatrixPassword;
    dbNextcloudPassword = secrets.dbNextcloudPassword;
    redisServerPassword = secrets.redisServerPassword;

    # === Centralized Database Server (Phase 2a — ENABLED) ===

    # PostgreSQL 17 Server
    postgresqlServerEnable = true;
    postgresqlServerPort = 5432;
    postgresqlServerDatabases = [ "plane" "rails_database_prod" "matrix" ];
    postgresqlServerUsers = [
      {
        name = "plane";
        passwordFile = "/etc/secrets/db-plane-password";
        ensureDBOwnership = true;
      }
      {
        name = "liftcraft";
        passwordFile = "/etc/secrets/db-liftcraft-password";
        ensureDBOwnership = false; # rails_database_prod owned separately
      }
      {
        name = "matrix";
        passwordFile = "/etc/secrets/db-matrix-password";
        ensureDBOwnership = true;
      }
    ];

    # MariaDB Server
    mariadbServerEnable = true;
    mariadbServerPort = 3306;
    mariadbServerDatabases = [ "nextcloud" ];
    mariadbServerUsers = [
      {
        name = "nextcloud";
        database = "nextcloud";
        passwordFile = "/etc/secrets/db-nextcloud-password";
      }
    ];

    # PgBouncer Connection Pooler
    pgBouncerEnable = true;
    pgBouncerPort = 6432;
    pgBouncerPoolMode = "transaction";
    pgBouncerMaxClientConn = 1000;
    pgBouncerDefaultPoolSize = 20;

    # Redis Server
    redisServerEnable = true;
    redisServerPort = 6379;
    redisServerMaxMemory = "2gb";
    redisServerPasswordFile = "/etc/secrets/redis-password";

    # === Database Backups (Phase 2a — ENABLED) ===
    postgresqlBackupEnable = true;
    mariadbBackupEnable = true;

    # Backup location (local disk — no NFS mount on VPS)
    databaseBackupLocation = "/var/backups/databases";

    # Daily backups (7 days retention, custom + SQL formats)
    databaseBackupStartAt = "*-*-* 02:00:00"; # Daily at 2 AM
    databaseBackupRetainDays = 7;

    # Hourly backups (3 days retention, custom format only for speed)
    databaseBackupHourlyEnable = true;
    databaseBackupHourlySchedule = "*:00:00"; # Every hour at :00
    databaseBackupHourlyRetainCount = 72; # 72 hourly backups = 3 days

    # Redis BGSAVE before backups (ensures cache consistency)
    redisBgsaveBeforeBackup = true;
    redisBgsaveTimeout = 60;

    # === Prometheus Database Exporters (Phase 2a — ENABLED) ===
    prometheusPostgresExporterEnable = true;
    prometheusPostgresExporterPort = 9187;
    prometheusMariadbExporterEnable = true;
    prometheusMariadbExporterPort = 9104;
    prometheusRedisExporterEnable = true;
    prometheusRedisExporterPort = 9121;

    # === SNMP Exporter (pfSense monitoring — migrated from LXC_monitoring) ===
    prometheusSnmpExporterEnable = true;
    prometheusSnmpCommunity = secrets.snmpCommunity;
    prometheusSnmpv3User = secrets.snmpv3User;
    prometheusSnmpv3AuthPass = secrets.snmpv3AuthPass;
    prometheusSnmpv3PrivPass = secrets.snmpv3PrivPass;
    prometheusSnmpTargets = [
      { name = "pfsense"; host = "192.168.8.1"; module = "pfsense"; }
    ];

    # === Graphite Exporter (TrueNAS metrics — migrated from LXC_monitoring) ===
    prometheusGraphiteEnable = true;
    prometheusGraphitePort = 9109;
    prometheusGraphiteInputPort = 2003;

    # === Cloudflare Tunnel (Phase 2b — ENABLED) ===
    cloudflaredEnable = true;

    # === Monitoring Stack (Phase 2d — ENABLED) ===
    grafanaEnable = true;
    grafanaLocalSslEnable = false; # No /mnt/shared-certs/ on VPS — use Cloudflare Tunnel for HTTPS
    # Disable standalone node exporter — grafana.nix runs its own on port 9091
    prometheusExporterEnable = false;
    prometheusExporterCadvisorEnable = false;

    # Domain settings (passed to grafana.nix for nginx virtual hosts)
    wildcardLocal = secrets.wildcardLocal;
    publicDomain = secrets.publicDomain;
    grafanaAlertsFrom = secrets.grafanaAlertsFrom;
    notificationToEmail = secrets.alertEmail;

    # Remote targets for Prometheus scraping (via WireGuard tunnel to LAN)
    # NOTE: All LXC containers decommissioned (Phase 4g complete)
    # TrueNAS monitored via Graphite exporter (port 2003), not node_exporter
    prometheusRemoteTargets = [];

    # Application metrics (local VPS databases only — LXC_database decommissioned)
    prometheusAppTargets = [
      # VPS local database exporters
      { name = "vps_postgresql"; host = "127.0.0.1"; port = 9187; }
      { name = "vps_mariadb";    host = "127.0.0.1"; port = 9104; }
      { name = "vps_redis";      host = "127.0.0.1"; port = 9121; }
      # Matrix Synapse metrics (VPS Docker)
      { name = "synapse";        host = "127.0.0.1"; port = 9000; }
    ];

    # Blackbox exporter (HTTP probes for public services)
    prometheusBlackboxEnable = true;
    prometheusBlackboxHttpTargets = [
      { name = "plane"; url = "https://plane.${secrets.publicDomain}"; }
      { name = "portfolio"; url = "https://${secrets.publicDomain}"; }
      { name = "leftyworkout_test"; url = "https://leftyworkout-test.${secrets.publicDomain}"; }
      { name = "grafana"; url = "https://grafana.${secrets.publicDomain}"; }
      { name = "matrix"; url = "https://matrix.${secrets.publicDomain}/_matrix/client/versions"; }
      { name = "element"; url = "https://element.${secrets.publicDomain}"; }
      { name = "headscale"; url = "https://${secrets.headscaleDomain}"; }
      { name = "status"; url = "https://status.${secrets.publicDomain}"; }
    ];
    prometheusBlackboxIcmpTargets = [
      { name = "pfsense"; host = "192.168.8.1"; }
      { name = "pve"; host = "192.168.8.82"; }
      { name = "truenas"; host = "192.168.20.200"; }
      { name = "wan"; host = "1.1.1.1"; }
    ];

    # === Docker Services (Phase 3B — service migration) ===
    homelabDockerEnable = true;
    homelabDockerStacks = [
      { name = "portfolio"; path = "portfolio"; }
      { name = "liftcraft"; path = "liftcraft"; }
      { name = "plane"; path = "plane"; }
      { name = "matrix"; path = "matrix"; }
      { name = "freshrss"; path = "freshrss"; }
      { name = "nextcloud"; path = "nextcloud"; }
      { name = "syncthing"; path = "syncthing"; }
      { name = "obsidian-remote"; path = "obsidian-remote"; }
      { name = "uptime-kuma"; path = "uptime-kuma"; }
    ];

    # ============================================================================
    # NATIVE POSTFIX RELAY (Phase 3 — via SMTP2GO, replaces LXC_mailer dependency)
    # ============================================================================
    postfixRelayEnable = true;
    postfixRelaySmtpUser = secrets.smtp2goUser;
    postfixRelaySmtpPassword = secrets.smtp2goPassword;

    # ============================================================================
    # EMAIL NOTIFICATIONS (Phase 3 — local Postfix relay)
    # ============================================================================
    notificationOnFailureEnable = true;
    smtpRelayHost = "localhost:25"; # Grafana uses local Postfix
    notificationSmtpHost = "127.0.0.1"; # msmtp uses local Postfix
    notificationSmtpPort = 25;
    notificationSmtpAuth = false;
    notificationSmtpTls = false;
    notificationFromEmail = secrets.notificationFrom;

    # ============================================================================
    # RESTIC BACKUP TO TRUENAS (Phase 3f — via Tailscale SFTP)
    # ============================================================================
    # Repos: databases (03:00), services (03:30), nextcloud (04:00)
    # Target: TrueNAS hddpool/vps-backups via Tailscale (100.64.0.9)
    vpsResticBackupEnable = true;
    vpsResticTarget = "100.64.0.9";       # TrueNAS Tailscale IP
    vpsResticTargetUser = "truenas_admin";
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
