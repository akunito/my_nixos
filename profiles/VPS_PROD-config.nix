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
    # Raised from the 6000 default: selection is per-question now, and the
    # longest published guide is ~6.3k on its own. At 6000 the best match
    # could not fit at all and arrived truncated.
    akucraftAskGuideMaxChars = 12000;
    # Both of these were raised on 2026-08-16 to protect a Chunky pregeneration
    # of the Overworld out to +-12000, which the normal 45-minute idle stop would
    # have killed within the first hour. It finished at 05:45 on 2026-08-17
    # (2,253,001 chunks, 100.00%, 13h30m, 2304 region files spanning region
    # -24..23 on both axes), so they are back to normal.
    akucraftIdleStopMinutes = 45;
    akucraftStopLockReason = "";
    # AkuTest is the second account used to try things in production without
    # putting Akunito's own character at risk. Nothing it does reaches Discord
    # or Telegram - including the names of bosses that are still secret.
    akucraftHiddenPlayers = [ "AkuTest" ];

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
    # OFF. It was on to read villager conversations and it never produced a
    # single one: litellm only dumps request/response bodies at DEBUG level,
    # so its journal carries nothing but access lines either way. The token
    # and truncation numbers that settled the villager tuning came from
    # llama-server's own log on DESK. Nothing is lost by leaving this off.
    litellmLogMessages = false;
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
      # Villagers run on DESK's own GPU, falling back to DeepSeek. Measured
      # 2026-08-17 on the real /ask prompt: a local model matches DeepSeek on
      # facts, refusals and NOT inventing answers, and is faster on short
      # replies (1.4-2.0s vs 2.4-3.6s) - which is what a villager needs, since
      # a player is standing in front of it. It is clearly worse at open-ended
      # advice, which is why /ask above stays on DeepSeek.
      #
      # 100.64.0.5 is DESK DIRECTLY, deliberately NOT the wake proxy on
      # 100.64.0.6:8090. Pointing at the proxy would send a Wake-on-LAN and
      # boot the desktop for two villager lines, which costs more in
      # electricity than the API calls it saves. Direct means: DESK off ->
      # connection refused in milliseconds -> DeepSeek answers. Same when the
      # GPU is busy gaming, since llama-server refuses to load above 5 GiB VRAM.
      { name = "akucraft-villager";
        # gpt-oss:20b with a COLON — Ollama's exact model name, and it is not
        # cosmetic. This said "openai/gpt-oss-20b" until 2026-09-01 and every
        # villager line 404'd to DeepSeek: llama-server served whatever single
        # model it had loaded and ignored the name in the request, Ollama does
        # not ("model 'gpt-oss-20b' not found"). It broke silently the day the
        # backend was swapped and stayed hidden because the model store was
        # empty too, so the local endpoint would have 404'd either way. Whenever
        # this alias changes, check it against `curl <desk>:8090/v1/models`.
        model = "openai/gpt-oss:20b";
        apiBase = "http://100.64.0.5:8090/v1";
        envVar = "";               # local server, no auth
        # This does NOT cover the "DESK is off" case - that one is a connection
        # refused in milliseconds and never reaches a timeout. It only bounds a
        # DESK that is awake but slow, so it has to clear a real generation.
        # Measured 2026-08-18 on live villager traffic: 77-503 completion
        # tokens, worst case 7.38s (503 tokens at 69 tok/s while the GPU was
        # also driving a Minecraft client). 8s sat right on top of that and
        # would have failed a long line over to paid DeepSeek for nothing.
        #
        # response_format is not cosmetic - it is the fix for llama.cpp
        # rejecting its own model's output. MCA hand-builds its request body
        # with only "model" and "messages" (decompiled OpenAIChatAI.class,
        # 7.7.32): no tools, no response_format, no max_tokens. It asks for
        # structure purely in the system prompt - "The reply MUST be in this
        # JSON format: {message, optionalCommand}" - and then parses
        # choices[0].message.content with Gson. Commands come back INSIDE that
        # JSON, never as OpenAI tool_calls.
        #
        # Left unconstrained, gpt-oss sometimes answers that demand by
        # borrowing the marker it knows from tool calling and emitting
        #   <|channel|>final <|constrain|>json<|message|>{"message":"..."}
        # on the FINAL channel. llama.cpp's harmony peg grammar does not
        # accept <|constrain|> there, throws away a perfectly good villager
        # line and returns HTTP 500 (~2 of 19 live requests, 2026-08-18).
        # litellm then quietly pays DeepSeek to redo it.
        #
        # Declaring the JSON contract on the request instead of only in the
        # prose sets up the grammar up front, so the model has no reason to
        # invent the marker. Safe precisely because MCA sends no tools: there
        # are no tool_calls for the grammar to suppress. Verified against the
        # real request shape - 12/12 clean, optionalCommand still emitted.
        extra = {
          # 10, not 20. Measured 2026-08-21: a TRUE cold start (backend stopped,
          # socket still armed - the state DESK sits in 15 minutes after the last
          # request) answers in 4.49s, and warm is 0.38s. So 10s clears every
          # case where DESK is actually going to answer.
          #
          # What it really bounds is the case the comment above gets wrong.
          # DESK asleep does NOT give "connection refused": llama-proxy.socket is
          # socket-activated, so when DESK is awake the port always accepts, and
          # when DESK is ASLEEP the SYN is simply never answered. Both hang.
          # Refused only happens under `llama-lock` (gaming). So this timeout is
          # the only thing standing between a sleeping desktop and a player
          # staring at a silent villager.
          timeout = 10;
          # Retrying a timeout against the same dead socket just pays the wait
          # again - 3 x 10s before the fallback even starts. Fail over instead.
          num_retries = 0;
          response_format = { type = "json_object"; };
          # gpt-oss reasons too, on its harmony "analysis" channel, and MCA picks
          # the token budget - so a long analysis returns finish_reason=length
          # with EMPTY content and the line falls through to paid DeepSeek.
          # Measured 2026-09-01 at max_tokens=80: unset gives an empty reply,
          # "low" gives valid JSON in 39-53 tokens, 3 of 3.
          #
          # "low", NOT "none". Unlike Qwen3.8, gpt-oss REQUIRES its analysis
          # channel: at "none" the reasoning field is empty but the model writes
          # its analysis into content instead ("We need to reply as a
          # villager...") and the JSON contract is broken. Same parameter,
          # opposite correct value, because the two models express thinking
          # differently.
          #
          # extra_body for the same reason as local-agent: litellm 1.75.5 drops
          # reasoning_effort for generic openai/ passthrough models.
          extra_body = { reasoning_effort = "low"; };
        }; }
      { name = "akucraft-villager-backup";
        model = "openai/deepseek-v4-flash";
        apiBase = "https://api.deepseek.com/v1";
        envVar = "DEEPSEEK_KEY_INGAME"; }

      # Agent work (Hermes) on DESK's own GPU — Qwen3.8-27B, dense, sub-Q4.
      # Deliberately NOT in any fallback chain and NOT used by the villagers:
      # it is the slow, strong model, and mixing it into a latency path would
      # undo the whole reason gpt-oss:20b is the primary.
      #
      # 100.64.0.6 is the WAKE PROXY, not DESK directly — the opposite choice
      # from akucraft-villager above, and for the opposite reason. Waking a
      # desktop for two villager lines costs more in electricity than the API
      # call it saves; waking it for an agent run that will burn thousands of
      # tokens on the GPU is exactly what the proxy is for.
      { name = "local-agent";
        model = "openai/qwen3.8-agent";
        apiBase = "http://100.64.0.6:8090/v1";
        envVar = "";               # local server, no auth
        extra = {
          # THE important one, and it has to go through extra_body.
          #
          # Qwen3.8 thinks by default. Ollama's /v1 endpoint takes the standard
          # `reasoning_effort`, and "none" turns thinking off — verified against
          # Ollama DIRECTLY: the reasoning field comes back empty.
          #
          # But litellm 1.75.5 (what nixpkgs pins) DROPS reasoning_effort for a
          # generic `openai/` passthrough model. It is silently swallowed both
          # from litellm_params and from the client's own request — measured
          # 2026-09-01, the request reached Ollama without it and came back
          # finish_reason=length with EMPTY content and a full reasoning_content.
          # That is the GLM-4.6V-Flash failure recorded in DESK-config, again.
          #
          # extra_body is merged verbatim into the outgoing JSON, so it survives
          # a gateway that does not know the parameter. Baking it in the model
          # instead is NOT possible: Ollama's Modelfile TEMPLATE is a Go
          # template, while the thinking switch lives in the GGUF's Jinja
          # chat template, which a Modelfile cannot replace.
          extra_body = { reasoning_effort = "none"; };
          # Sampling: only what /v1 accepts. temperature/top_p match Qwen's
          # official non-thinking profile; top_k and min_p are unsupported on
          # this endpoint and live in the Modelfile on DESK instead.
          temperature = 0.7;
          top_p = 0.8;
          # WoL (up to 120s) + a cold load of ~12 GiB of weights + a dense-27B
          # generation. Nothing like the villagers' 10s, and it must not be:
          # this path is allowed to be slow, it is not allowed to fail over.
          timeout = 300;
          num_retries = 0;
        }; }
    ];
    # 1, not the module default of 2. The retry budget multiplies BEFORE any
    # fallback runs, and the client has its own deadline: akucraft-bot's
    # ASK_TIMEOUT is 60s. At 2 the primary alone burns 3 x 20s = 60s, so the bot
    # gave up at the exact moment litellm would have started asking the backup.
    # At 1: 2 x 20s = 40s, leaving 20s for the fallback inside the deadline.
    #
    # NOT 0. Zero would be right if the fallback chain were real, but
    # `akucraft-support-backup` has no key - there is no Qwen subscription - so
    # it answers AuthenticationError instantly and the fallback is decorative.
    # With no working backup, one retry is the only resilience against a
    # transient DeepSeek 429 or 5xx, and it still fits the budget.
    litellmNumRetries = 1;

    litellmFallbacks = {
      akucraft-support = [ "akucraft-support-backup" ];
      # GPU first, then DeepSeek, then the third-party backup if DeepSeek is
      # down too.
      akucraft-villager = [ "akucraft-villager-backup" "akucraft-support-backup" ];
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
      # AkuCraft BlueMap. It used to sit at "/" on the players' own port 8100,
      # the address the invite email tells guests to open — so the live world
      # map was handed to every guest. akucraft-web now serves the mod pack on
      # 8100 and BlueMap on 127.0.0.1:8102, and this vhost is one of the two
      # authenticated ways in. Named to match the public Cloudflare hostname
      # akucraft-map.akunito.com, which fronts the same port behind Pocket ID.
      akucraft-map = { port = 8102; };
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
