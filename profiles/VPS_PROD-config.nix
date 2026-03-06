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
    # Split DNS: remote Tailscale clients resolve *.local.akunito.com via pfSense
    # Uses pfSense Tailscale IP (100.64.0.7) so DNS works over mesh without subnet routing
    headscaleDnsSplit = { "${secrets.wildcardLocal}" = [ "100.64.0.7" ]; };
    headscaleDnsSearchDomains = [ secrets.wildcardLocal ];

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

    # === Docker subnet access for rootless Docker containers (SEC-DOCKER-DB-001) ===
    # Per-user-per-database ACLs — each container can only reach its own database.
    # 10.0.0.0/8 covers slirp4netns NAT (rootless Docker); 172.16.0.0/12 covers Docker bridge networks.
    postgresqlServerAuthentication = ''
      host    plane              plane           10.0.0.0/8        scram-sha-256
      host    plane              plane           172.16.0.0/12     scram-sha-256
      host    rails_database_prod liftcraft      10.0.0.0/8        scram-sha-256
      host    rails_database_prod liftcraft      172.16.0.0/12     scram-sha-256
      host    matrix             matrix          10.0.0.0/8        scram-sha-256
      host    matrix             matrix          172.16.0.0/12     scram-sha-256
      host    miniflux           miniflux        10.0.0.0/8        scram-sha-256
      host    miniflux           miniflux        172.16.0.0/12     scram-sha-256
      host    vaultwarden        vaultwarden     10.0.0.0/8        scram-sha-256
      host    vaultwarden        vaultwarden     172.16.0.0/12     scram-sha-256
      host    n8n                n8n             10.0.0.0/8        scram-sha-256
      host    n8n                n8n             172.16.0.0/12     scram-sha-256
    '';

    # === Database Credentials (from git-crypt encrypted secrets/domains.nix) ===
    dbPlanePassword = secrets.dbPlanePassword;
    dbLiftcraftPassword = secrets.dbLiftcraftPassword;
    dbMatrixPassword = secrets.dbMatrixPassword;
    dbMinifluxPassword = secrets.dbMinifluxPassword;
    dbN8nPassword = secrets.dbN8nPassword;
    dbVaultwardenPassword = secrets.dbVaultwardenPassword;
    vaultwardenAdminToken = secrets.vaultwardenAdminToken;
    dbNextcloudPassword = secrets.dbNextcloudPassword;
    redisServerPassword = secrets.redisServerPassword;

    # === Centralized Database Server (Phase 2a — ENABLED) ===

    # PostgreSQL 17 Server
    postgresqlServerEnable = true;
    postgresqlServerPort = 5432;
    postgresqlServerDatabases = [ "plane" "rails_database_prod" "matrix" "miniflux" "vaultwarden" "n8n" ];
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
      {
        name = "miniflux";
        passwordFile = "/etc/secrets/db-miniflux-password";
        ensureDBOwnership = true;
      }
      {
        name = "vaultwarden";
        passwordFile = "/etc/secrets/db-vaultwarden-password";
        ensureDBOwnership = true;
      }
      {
        name = "n8n";
        passwordFile = "/etc/secrets/db-n8n-password";
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

    # Periodic local backups (custom format only for speed)
    databaseBackupHourlyEnable = true;
    databaseBackupHourlySchedule = "*:00:00"; # PostgreSQL: every hour at :00
    mariadbHourlySchedule = "*-*-* 00,06,12,18:00:00"; # MariaDB: every 6 hours
    databaseBackupHourlyRetainCount = 72; # PostgreSQL: 72 hourly = 3 days; MariaDB: 72 x 6h = 18 days

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
    prometheusExporterLocalOnly = true; # Bind all exporters to 127.0.0.1 (SEC-AUDIT-001)

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

    # === ACME Wildcard Certificate (for *.local.akunito.com) ===
    acmeEnable = true;
    acmeCopyToSharedCerts = false; # No Proxmox shared mount on VPS

    # === NFS Server (romm-library export — Tailscale, LAN, TrueNAS) ===
    nfsServerEnable = true;
    nfsExports = ''
      /home/akunito/romm-library  100.64.0.0/10(rw,sync,no_subtree_check,root_squash) 192.168.8.0/24(rw,sync,no_subtree_check,root_squash) 192.168.20.0/24(rw,sync,no_subtree_check,root_squash)
    '';

    # === Vaultwarden (Password Manager — NixOS native, PostgreSQL backend) ===
    vaultwardenEnable = true;
    vaultwardenDomain = "vault.${secrets.publicDomain}";
    vaultwardenPort = 8222;

    # === Cloudflare Tunnel (Phase 2b — ENABLED) ===
    cloudflaredEnable = true;

    # === Nginx Local Access (*.local.akunito.com via Tailscale — bypasses Cloudflare Access) ===
    nginxLocalEnable = true;
    nginxLocalListenAddress = "100.64.0.6"; # VPS Tailscale IP
    nginxLocalServices = {
      grafana    = { port = 3002; };
      prometheus = { port = 9090; basicAuthFile = "/etc/nginx/auth/prometheus.htpasswd"; };
      matrix     = { port = 8008; };
      element    = { port = 8088; };
      miniflux   = { port = 8084; };
      nextcloud  = { port = 8089; };
      syncthing  = { port = 8384; };
      status     = { port = 3009; };
      plane      = { port = 3003; };
      unifi      = { port = 8443; https = true; };
      portfolio  = { port = 3005; };
      vault      = { port = 8222; };
      emulators  = { port = 8998; };
      calibre    = { port = 8083; };
      n8n        = { port = 5678; };
      openclaw   = { port = 18789; };
    };

    # === Monitoring Stack (Phase 2d — ENABLED) ===
    grafanaEnable = true;
    grafanaLocalSslEnable = false; # No /mnt/shared-certs/ on VPS — use Cloudflare Tunnel for HTTPS
    prometheusBasicAuthHtpasswd = secrets.prometheusHtpasswd; # HTTP Basic Auth for prometheus.local.akunito.com
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
      # Miniflux RSS reader (exposes /metrics natively)
      { name = "miniflux";      host = "127.0.0.1"; port = 8084; }
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
      { name = "miniflux"; url = "https://freshrss.${secrets.publicDomain}"; }
    ];
    prometheusBlackboxIcmpTargets = [
      { name = "pfsense"; host = "192.168.8.1"; }
      { name = "pve"; host = "192.168.8.82"; }
      { name = "truenas"; host = "192.168.20.200"; }
      { name = "wan"; host = "1.1.1.1"; }
    ];

    # === OpenClaw Sanitizers (CSV + memory file injection stripping) ===
    openclawSanitizersEnable = true;

    # === Docker Services (Phase 3B — service migration) ===
    homelabDockerEnable = true;
    homelabDockerStacks = [
      { name = "portfolio"; path = "portfolio"; }
      { name = "liftcraft"; path = "liftcraft"; }
      { name = "plane"; path = "plane"; }
      { name = "matrix"; path = "matrix"; }
      { name = "miniflux"; path = "miniflux"; }
      { name = "miniflux-ai"; path = "miniflux-ai"; }
      { name = "nextcloud"; path = "nextcloud"; }
      { name = "syncthing"; path = "syncthing"; }
      { name = "uptime-kuma"; path = "uptime-kuma"; }
      { name = "unifi"; path = "unifi"; }
      { name = "romm"; path = "romm"; }
      { name = "calibre"; path = "calibre"; }
      { name = "n8n"; path = "n8n"; }
      { name = "openclaw"; path = "openclaw"; }
    ];

    # ============================================================================
    # NATIVE POSTFIX RELAY (Phase 3 — via SMTP2GO, replaces LXC_mailer dependency)
    # ============================================================================
    postfixRelayEnable = true;
    postfixRelaySmtpUser = secrets.smtp2goUser;
    postfixRelaySmtpPassword = secrets.smtp2goPassword;
    # Rootless Docker containers connect via VPS public IP (slirp4netns NAT)
    postfixRelayExtraNetworks = [ "${secrets.vpsNetcupIp}/32" ];

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
    # Repos: databases (19:00), services (19:30), nextcloud (Sun 20:00), libraries (Sun 20:30)
    # Window: 19:00-22:00 (TrueNAS sleeps 23:00-11:00)
    # Target: TrueNAS via Tailscale (100.64.0.10)
    # databases → ssdpool/vps-backups (critical), services+libraries+nextcloud → extpool/vps-backups
    vpsResticBackupEnable = true;
    vpsResticTarget = "100.64.0.10";      # TrueNAS Tailscale IP
    vpsResticTargetUser = "truenas_admin";
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
