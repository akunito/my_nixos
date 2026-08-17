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

    # Auto-updates (weekly Saturday morning, before backup window 19:00-22:00)
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 08:00:00";
    autoUpgradeRestartDocker = true;
    autoUserUpdateBranch = "release-25.11";

    # System packages (extends base with database CLI tools)
    systemPackages = pkgs: pkgs-unstable:
      (base.systemSettings.systemPackages pkgs pkgs-unstable) ++ [
        pkgs.postgresql_17
        pkgs.mariadb
        pkgs.redis
        pkgs.curl  # For healthchecks
        pkgs.olm  # libolm for Matrix bot E2E encryption
        pkgs.gitleaks  # Secret scanning for repo audits
      ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Tailscale (Phase 1 — first thing needed) ===
    # Pull prebuilt paths from DESK's harmonia cache before cache.nixos.org
    # (priority 30 vs 40) over Tailscale. Extra substituter only — cache.nixos.org
    # stays, and fallback + connect-timeout mean a sleeping DESK costs seconds.
    nixBinaryCacheSubstituters = [ "http://100.64.0.5:5000" ];
    nixBinaryCachePublicKeys = [ "nixosaku-1:a1t91oU1udPpLWvLr8lWwj2kS5a7lPxhH38p094Ps+s=" ];
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${secrets.headscaleDomain}";
    tailscaleAcceptRoutes = true; # Accept routes from home subnet router
    tailscaleAcceptDns = true;

    # === Package Modules ===
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = false;

    # === Development Tools & AI ===
    claudeCodeEnable = true; # Lightweight Claude Code (CLI + settings + MCP) for Matrix bot interface
    perplexityApiKey = secrets.perplexityApiKey; # Perplexity API key for MCP server
    planeApiToken = secrets.planeApiToken; # Plane API token for Claude Code MCP
    # Internal Tailscale vhost, NOT the public host: plane.<publicDomain> sits
    # behind Cloudflare Access, which rejects at the edge before Plane ever sees
    # the API token — the MCP just gets the Access login page as HTML.
    planeApiUrl = "https://plane.${secrets.wildcardLocal}";
    planeWorkspaceSlug = "akuworkspace";

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
    # AkuCraft friendly name — MagicDNS A record so Minecraft clients (family
    # AND isolated mc-guest nodes) can use a hostname instead of 100.64.0.6.
    # One name serves both servers: survival is the default port (25565),
    # creative is akucraft.<domain>:25566.
    headscaleExtraDnsRecords = [
      { name = "akucraft.${secrets.wildcardLocal}"; type = "A"; value = "100.64.0.6"; }
    ];
    # Telegram bot posting AkuCraft server up/down + player join/leave to the
    # AkuCraft group. No-ops until akucraftTelegramBotToken/ChatId are set in secrets.
    akucraftStatusBotEnable = true;
    # /ask - private LLM support in Discord, through the LiteLLM gateway below.
    akucraftAskEnable = true;
    akucraftAskDailyQuota = 25;
    akucraftAskQuotaOverrides = { Akunito = 60; }; # applies once Akunito has /link-ed
    # Both of these were raised on 2026-08-16 to protect a Chunky pregeneration
    # of the Overworld out to +-12000, which the normal 45-minute idle stop would
    # have killed within the first hour. It finished at 05:45 on 2026-08-17
    # (2,253,001 chunks, 100.00%, 13h30m, 2304 region files spanning region
    # -24..23 on both axes), so they are back to normal.
    akucraftIdleStopMinutes = 45;
    akucraftStopLockReason = "";

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
      host    linkwarden         linkwarden      10.0.0.0/8        scram-sha-256
      host    linkwarden         linkwarden      172.16.0.0/12     scram-sha-256
    '';
    # Note: Docker's default pool 172.17–172.31 is exhausted on this host, so
    # newly created bridge networks now land in 192.168.x and fall outside both
    # ranges above. Any future stack that talks to this PostgreSQL must pin its
    # network subnet inside 172.16.0.0/12 (as ~/.homelab/linkwarden does with
    # 172.16.0.0/24, which is below Docker's pool and never auto-assigned).

    # === Database Credentials (from git-crypt encrypted secrets/domains.nix) ===
    dbPlanePassword = secrets.dbPlanePassword;
    dbLiftcraftPassword = secrets.dbLiftcraftPassword;
    dbMatrixPassword = secrets.dbMatrixPassword;
    dbMinifluxPassword = secrets.dbMinifluxPassword;
    dbLinkwardenPassword = secrets.dbLinkwardenPassword;
    dbN8nPassword = secrets.dbN8nPassword;
    dbVaultwardenPassword = secrets.dbVaultwardenPassword;
    vaultwardenAdminToken = secrets.vaultwardenAdminToken;
    dbNextcloudPassword = secrets.dbNextcloudPassword;
    redisServerPassword = secrets.redisServerPassword;

    # === Centralized Database Server (Phase 2a — ENABLED) ===

    # PostgreSQL 17 Server
    postgresqlServerEnable = true;
    postgresqlServerPort = 5432;
    postgresqlServerDatabases = [ "plane" "rails_database_prod" "matrix" "miniflux" "vaultwarden" "n8n" "linkwarden" ];
    postgresqlServerUsers = [
      {
        name = "plane";
        passwordFile = "/etc/secrets/db-plane-password";
        ensureDBOwnership = true;
      }
      {
        name = "linkwarden";
        passwordFile = "/etc/secrets/db-linkwarden-password";
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

    # === Graphite Exporter (DISABLED — TrueNAS migrated to NixOS, metrics now via node-exporter) ===
    prometheusGraphiteEnable = false;

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
    # Apex sender: every other service relays as <service>@<publicDomain> and
    # SMTP2GO verifies the apex domain. The old default produced the subdomain
    # vault@vault.<publicDomain>.
    vaultwardenSmtpFrom = "vault@${secrets.publicDomain}";
    vaultwardenPort = 8222;

    # === Cloudflare Tunnel (Phase 2b — ENABLED) ===
    cloudflaredEnable = true;

    # === Local LLM wake-and-wait proxy (fronts DESK's llama-server) ===
    # Apps use http://100.64.0.6:8090/v1 ; this wakes DESK via pfSense WoL if
    # asleep, waits, then forwards to DESK (100.64.0.5:8090). See memory reference_desk_wol.
    llamaWakeProxyEnable = true;
    llamaWakeProxyListenAddress = "100.64.0.6"; # VPS Tailscale IP
    llamaWakeProxyWolMac = "08:bf:b8:6c:ab:92"; # DESK onboard 2.5GbE (eno1)

    # === LiteLLM gateway (AkuCraft AI: MCA villagers + akucraft-bot /ask) ===
    # Bound to the Tailscale IP because the rootless `minecraft` container
    # cannot reach the host's 127.0.0.1 (verified: 302 in 1.3 ms to this IP).
    # ‼️ Do NOT add port 4000 to the tag:mc-guest headscale ACL.
    litellmEnable = true;
    litellmHost = "100.64.0.6"; # VPS Tailscale IP
    # NOT 4000 (litellm's own default): rpc.statd from the NFS server holds
    # 4000-4002 on this host. litellm does not fail on a taken port, it silently
    # binds elsewhere — which once made the tailscale0 rule below expose statd
    # instead. The ExecStartPost assertion in the module now catches that.
    litellmPort = 4711;
    litellmOpenFirewallTailscale = true;
    # ⚠️ ON while the villager prompts are being tuned - it also logs every
    # player /ask question, so turn it back off once they are settled.
    litellmLogMessages = true;
    # One DeepSeek key per consumer: spend is attributable in the provider
    # dashboard and either can be revoked without taking the other down. They
    # share one account balance, so this is attribution, not separate budgets.
    litellmProviders = [
      { envVar = "DEEPSEEK_KEY_DISCORD"; secret = "deepseekApiKeyDiscord"; }
      { envVar = "DEEPSEEK_KEY_INGAME"; secret = "deepseekApiKeyIngame"; }
      { envVar = "QWEN_API_KEY"; secret = "qwenApiKey"; }
    ];
    # Model ids verified against the provider itself, not a price tracker:
    #   curl https://api.deepseek.com/v1/models -H "Authorization: Bearer $KEY"
    #   -> deepseek-v4-flash, deepseek-v4-pro   (2026-08-16)
    # The generic `openai/` prefix is deliberate — see the version note in
    # system/app/litellm.nix.
    litellmModels = [
      { name = "akucraft-support";
        model = "openai/deepseek-v4-flash";
        apiBase = "https://api.deepseek.com/v1";
        envVar = "DEEPSEEK_KEY_DISCORD"; }
      { name = "akucraft-support-backup";
        model = "openai/qwen-flash";
        apiBase = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1";
        envVar = "QWEN_API_KEY"; }
      # Villagers get their own alias so the model can be chosen on LATENCY
      # (a player is standing in front of them) independently of /ask. Which
      # backend wins is decided by measurement, not by the price table.
      { name = "akucraft-villager";
        model = "openai/deepseek-v4-flash";
        apiBase = "https://api.deepseek.com/v1";
        envVar = "DEEPSEEK_KEY_INGAME"; }
    ];
    litellmFallbacks = {
      akucraft-support = [ "akucraft-support-backup" ];
      akucraft-villager = [ "akucraft-support-backup" ];
    };

    # === Nginx Local Access (*.local.akunito.com via Tailscale — bypasses Cloudflare Access) ===
    nginxLocalEnable = true;
    nginxLocalListenAddress = "100.64.0.6"; # VPS Tailscale IP (must be IP, not hostname — nginx bind)
    nginxLocalServices = {
      grafana    = { port = 3002; };
      prometheus = { port = 9090; basicAuthFile = "/etc/nginx/auth/prometheus.htpasswd"; };
      matrix     = { port = 8008; };
      element    = { port = 8088; };
      miniflux   = { port = 8084; };
      freshrss   = { port = 8084; };
      nextcloud  = { port = 8089; };
      pictures   = { port = 2283; maxBodySize = "4G"; };  # Immich (large photo/video uploads)
      pictures-dev = { port = 2284; maxBodySize = "4G"; };  # Immich dev/compression clone (temporary)
      syncthing  = { port = 8384; };
      status     = { port = 3009; };
      plane      = { port = 3003; };
      plane-dev  = { port = 3007; maxBodySize = "50M"; };  # isolated Plane dev/test clone (own pg/redis/mq/minio)
      unifi      = { port = 8443; https = true; };
      portfolio  = { port = 3005; };
      # Linkwarden — self-hosted bookmarks, replacing Raindrop.io. maxBodySize
      # because it archives pages as PDF/screenshot and imports run as one
      # multipart upload (the Raindrop export is ~1300 bookmarks).
      links      = { port = 3011; maxBodySize = "256M"; };
      # /admin denied here on purpose: the Vaultwarden admin panel is guarded
      # only by ADMIN_TOKEN, so it must stay behind Cloudflare Access on the
      # public host rather than be open to every group:family tailnet device.
      # maxBodySize: this vhost is now the path every native Bitwarden client
      # uses, and it inherited NixOS's default client_max_body_size of 10m, so
      # attachments above that failed with 413. Bitwarden caps attachments at
      # 100 MB, so 128M clears it with headroom.
      vault      = { port = 8222; maxBodySize = "128M"; denyPaths = [ "/admin" ]; };
      emulators  = { port = 8998; };
      calibre    = { port = 8083; };
      n8n        = { port = 5678; };
      openclaw   = { port = 18789; };
      finance    = { port = 8190; maxBodySize = "50M"; };
    };

    # === Monitoring Stack (Phase 2d — ENABLED) ===
    grafanaEnable = true;
    grafanaLocalSslEnable = false; # No /mnt/shared-certs/ on VPS — use Cloudflare Tunnel for HTTPS
    grafanaOauthClientId = secrets.grafanaOauthClientId;         # Pocket ID OIDC (auth.akunito.com)
    grafanaOauthClientSecret = secrets.grafanaOauthClientSecret;
    prometheusBasicAuthHtpasswd = secrets.prometheusHtpasswd; # HTTP Basic Auth for prometheus.local.akunito.com
    financeUser = secrets.financeUser; # Flask app auth for finance-tagger
    financePassword = secrets.financePassword; # Flask app auth for finance-tagger
    # Disable standalone node exporter — grafana.nix runs its own on port 9091
    prometheusExporterEnable = false;
    prometheusExporterCadvisorEnable = true;
    prometheusCadvisorDockerSocket = "unix:///run/user/1000/docker.sock";  # Rootless Docker
    prometheusCadvisorContainerdSocket = "/run/user/1000/docker/containerd/containerd.sock";

    # Domain settings (passed to grafana.nix for nginx virtual hosts)
    wildcardLocal = secrets.wildcardLocal;
    publicDomain = secrets.publicDomain;
    grafanaAlertsFrom = secrets.grafanaAlertsFrom;
    notificationToEmail = secrets.alertEmail;
    grafanaTelegramBotToken = secrets.grafanaTelegramBotToken or "";
    grafanaTelegramChatId = secrets.grafanaTelegramChatId or "";

    # Remote targets for Prometheus scraping (via WireGuard/Tailscale tunnel to LAN)
    # NAS: node-exporter (9100) + cadvisor (8081) on rootless Docker
    # Laptops use Tailscale IPs (roaming — not always on LAN)
    prometheusRemoteTargets = [
      { name = "nas"; host = "192.168.20.200"; nodePort = 9100; cadvisorPort = 8081; }
      { name = "desk"; host = "nixosaku"; nodePort = 9100; cadvisorPort = null; }  # Tailscale hostname (workstation VLAN not routed over tailnet)
      { name = "x13"; host = "nixosx13aku"; nodePort = 9100; cadvisorPort = null; }  # Tailscale hostname (roaming)
      { name = "laptop_a"; host = "nixosaga"; nodePort = 9100; cadvisorPort = null; }  # Tailscale hostname (roaming)
    ];

    # Application metrics (local VPS databases only — LXC_database decommissioned)
    prometheusAppTargets = [
      # VPS local database exporters
      { name = "postgresql"; host = "127.0.0.1"; port = 9187; }
      { name = "mariadb";    host = "127.0.0.1"; port = 9104; }
      { name = "redis";      host = "127.0.0.1"; port = 9121; }
      # Matrix Synapse metrics (VPS Docker)
      { name = "synapse";   host = "127.0.0.1"; port = 9000; }
      # Miniflux RSS reader (exposes /metrics natively)
      { name = "miniflux";  host = "127.0.0.1"; port = 8084; }
      # TrueNAS exportarr targets (via WireGuard tunnel to LAN)
      { name = "sonarr";    host = "192.168.20.200"; port = 9707; }
      { name = "radarr";    host = "192.168.20.200"; port = 9708; }
      { name = "prowlarr";  host = "192.168.20.200"; port = 9709; }
      { name = "bazarr";    host = "192.168.20.200"; port = 9710; }
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
      { name = "truenas"; host = "192.168.20.200"; }
      { name = "wan"; host = "1.1.1.1"; }
      { name = "wireguard_tunnel"; host = "172.26.5.155"; }   # VPS WireGuard tunnel (self-ping)
      { name = "switch_usw_aggr"; host = "192.168.8.180"; }   # UniFi Aggregation Switch
      { name = "switch_usw_24"; host = "192.168.8.181"; }     # UniFi 24-port Switch
      { name = "lan_wifi"; host = "192.168.8.2"; }            # LAN WiFi AP
      { name = "guest_wifi"; host = "192.168.9.2"; }          # Guest WiFi AP (offline)
    ];

    # === OpenClaw Sanitizers (CSV + memory file injection stripping) ===
    openclawSanitizersEnable = true;

    # === OpenClaw Matrix Bridge (E2E encrypted Matrix channels + Telegram fallback) ===
    openclawMatrixBridgeEnable = true;

    # === Docker Services (Phase 3B — service migration) ===
    homelabDockerEnable = true;
    homelabDockerStacks = [
      { name = "portfolio"; path = "portfolio"; }
      { name = "plane"; path = "plane"; }
      { name = "matrix"; path = "matrix"; }
      { name = "nextcloud"; path = "nextcloud"; }
      { name = "syncthing"; path = "syncthing"; }
      { name = "uptime-kuma"; path = "uptime-kuma"; }
      { name = "unifi"; path = "unifi"; }
      { name = "romm"; path = "romm"; }
      { name = "calibre"; path = "calibre"; }
      { name = "n8n"; path = "n8n"; }
      { name = "immich"; path = "immich"; }
      { name = "pocket-id"; path = "pocket-id"; }
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
    notificationTelegramOnFailureEnable = true; # Send Telegram alerts on service failure (via @infra_alerts_aku_bot)
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
    # Window: 19:00-22:00 (NAS sleeps 23:00-16:00)
    # Target: NAS via Tailscale hostname (nas-aku)
    # databases → ssdpool/vps-backups (critical), services+libraries+nextcloud → extpool/vps-backups
    vpsResticBackupEnable = true;
    vpsResticTarget = "nas-aku";           # NAS Tailscale hostname (resolves via MagicDNS)
    vpsResticTargetUser = "akunito";  # NixOS NAS uses akunito (no truenas_admin user)
    # Restic repo passwords (from git-crypt secrets/domains.nix). Deployed to
    # /etc/secrets/restic-* by restic-backup-vps.nix so they survive
    # reboots/redeploys — previously placed by hand and silently vanished,
    # breaking the scheduled backups (nextcloud, 2026-07).
    resticDatabasesPassword = secrets.resticDatabasesPassword;
    resticServicesPassword = secrets.resticServicesPassword;
    resticNextcloudPassword = secrets.resticNextcloudPassword;
    resticImmichPassword = secrets.resticImmichPassword;

    # === Backup Monitoring (pfSense config + NAS restic repos) ===
    prometheusPfsenseBackupEnable = true;
    prometheusNasBackupEnable = true;

    # === NAS Offsite Backup (VPS pulls Docker data + configs daily) ===
    nasResticBackupEnable = true;
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
