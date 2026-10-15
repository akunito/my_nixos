# NAS_PROD Profile Configuration
# NixOS replacement for TrueNAS SCALE on the storage server
# Hardware: B550 AORUS ELITE V2, Ryzen 5 5600G, 62GB RAM
# Storage: ssdpool (1x Samsung 870 QVO 4TB SATA, encrypted; single disk since 2026-10-14, AINF-406), extpool (4TB NVMe PCIe)
# Network: 2x10GbE LACP bond (VLAN 100), 2.5GbE LAN fallback

let
  secrets = import ../secrets/domains.nix;
in
{
  useRustOverlay = false;

  systemSettings = {
    hostname = "nas-aku";
    profile = "homelab";
    envProfile = "NAS_PROD";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles NAS_PROD -s -u";
    # The 3090 is the only GPU anything here configures. The 5600G iGPU needs no
    # settings: amdgpu binds by modalias and keeps renderD128 for Jellyfin, because
    # nvidia.nix keeps nvidia_drm unloaded (no second /dev/dri node).
    gpuType = "nvidia";
    nvidiaPersistencedEnable = true;
    nvidiaPowerManagementEnable = true;   # nightly S3 23:00 -> 16:00
    nvidiaContainerToolkitEnable = true;  # AI stacks (llama.cpp / vLLM / whisper) in rootless + rootful docker
    nvidiaPowerLimitWatts = 300;          # ESTIMATE, not measured. Stock cap: read "Default Power Limit" in `nvidia-smi -q -d POWER`; re-tune from measured tok/s per W.
    nvidiaGpuExporterEnable = true;       # :9835, scraped by VPS Prometheus over tailscale0
    # AINF-403: the 3090's own "off" mode leaves a white LED lit (measured 2026-10-02); direct
    # black turns everything off but is volatile, hence rgb-off re-runs at boot + resume.
    # IT5702 (RGB Fusion 2) has no Off mode → static black. Front power LED is on F_PANEL.
    rgbOffOpenrgbArgs = [ "-d" "RTX 3090" "-m" "direct" "-c" "000000" "-d" "B550" "-m" "static" "-c" "000000" ];

    # === Reasoner preset: llama.cpp on the 3090, on-demand (0 VRAM idle) ===
    # Qwen3.8-27B abliterated (huihui-ai, Apache-2.0), Unsloth UD-Q4_K_XL 17.4 GB,
    # pre-downloaded by hand (sha256 ebbc66b4…) — no -hf, the file is the model.
    # Thinking mode is Qwen3.8's default; sampling = Qwen's thinking-mode card
    # values. Port 8090 on tailscale0 only; the backend stops after 15 min idle
    # and before S3. Plan: docs/akunito/plans/nas-3090-ai-presets.md
    llamaServerEnable = true;
    llamaServerIdleTimeout = "infinity";  # never unload on idle (Diego, 2026-10-14): measured 7.5 W unloaded vs 7.6 W loaded at P8 (30 s avg), 0.04 % CPU, 414 MB RAM — unloading buys nothing while nothing else wants the card. Still stops before S3 (Conflicts=sleep.target); the preset manager (F1) will unload on a preset change
    llamaServerBackend = "docker-cuda";   # MEASURED 2026-10-13: Vulkan/NVIDIA ICD 48 pp / 36 tg tok/s; CUDA image 1326 pp / 40 tg, load 10 s
    llamaServerModelFile = "/var/lib/llama-server/models/Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf";
    llamaServerCtxSize = 131072;          # KV is 64 KB/token in f16 (256k asked for a 16 GB KV buffer and OOMed on 2026-10-14; weights 17.4 GB). 128k with q8_0 KV = ~4 GB. 256k (= n_ctx_train) only fits with q4_0 KV — not worth the recall loss on a Q4 27B
    llamaServerParallelSlots = 1;         # Claude Code / OpenCode are one stream; a second client queues
    llamaServerModelAlias = "qwen3.8-27b-abliterated";   # the id OpenCode / claude-nas use; llama-server accepts any model name anyway (verified), this only makes /v1/models honest
    llamaServerChatTemplateFile = ../system/app/llama-server/templates/qwen3.8-system-anywhere.jinja;   # Claude Code sends a role=system "# Environment" message after the first user turn; the GGUF's template raises on it (every request 500 on 2026-10-14)
    llamaServerExtraArgs = [ "--jinja" "--temp" "1.0" "--top-p" "0.95" "--top-k" "20" "--min-p" "0.0" "-fa" "on" ];   # sampling only (Qwen thinking-mode card); -fa on is what q8_0/q4_0 KV needs. KV type: llamaServerKvType
    llamaServerKvType = "q8_0";            # q8_0 KV halves the cache (needs -fa on); near-lossless. Presets override it (ai-presets.nix)
    llamaServerVramBusyBytes = 2147483648; # nothing else may hold the card: 24 GB - 17.4 GB weights

    # NAS 3090 preset manager (system/app/ai-presets.nix): `ai preset set NAME`,
    # Waybar custom/nas-llm + rofi on DESK. KV per token MEASURED 2026-10-14 on
    # Qwen3.8-27B: 64 KB f16, 32 KB q8_0, ~16 KB q4_0; weights 17.4 GB, ~5 GB
    # left for KV. 256k (n_ctx_train) only fits with q4_0 KV (f16 OOMed).
    # Qwen3.6-35B-A3B: 10 of 40 layers are full attention, 2 KV heads x 256 ->
    # 20 KB/token f16 (computed from config.json, NOT measured yet).
    aiPresetsEnable = true;
    # capture-hub (system unit): Elgato 4K X on the NAS (UVC needs kernel >= 6.19, AINF-404; waits for the device until then).
    # API on the tailnet so DESK / VPS (Hermes) can pull frames and ask the VLM.
    captureHubEnable = true;
    captureHubListen = "100.64.0.1:8095";
    # Router mode (2026-10-14, Diego: verified first, then migrate): the model
    # is the request's `model` name (= aiPresets names); claude-nas / OpenCode /
    # the Waybar widget all switch the 3090 by naming a preset. Measured
    # eviction under --models-max 1 in llama-server.nix's comment.
    llamaServerRouter = true;
    aiPresetsDefault = "reasoner-128k";
    aiPresets = let
      reasoner = {
        model = "Huihui-Qwen3.8-27B-abliterated-UD-Q4_K_XL.gguf";
        alias = "qwen3.8-27b-abliterated";
        template = ../system/app/llama-server/templates/qwen3.8-system-anywhere.jinja;
        # Qwen3.8's template defaults reasoning_effort to xhigh: a claude-nas web-research
        # session thought past Claude Code's 32000-token output limit and died (2026-10-14).
        extra = [ "--jinja" "--temp" "1.0" "--top-p" "0.95" "--top-k" "20" "--min-p" "0.0" "-fa" "on"
                  "--reasoning-effort" "medium" "--reasoning-budget" "16384" ];
      };
    in {
      reasoner-128k = reasoner // {
        label = "Reasoner Qwen3.8-27B · 1×128k · KV q8_0";
        short = "R 128k"; vramEst = "21.1 GB"; ctx = 131072; slots = 1; kv = "q8_0";
      };
      reasoner-256k = reasoner // {
        label = "Reasoner Qwen3.8-27B · 1×256k · KV q4_0";
        short = "R 256k"; vramEst = "22.0 GB"; ctx = 262144; slots = 1; kv = "q4_0";
      };
      reasoner-2x128k = reasoner // {
        label = "Reasoner Qwen3.8-27B · 2×128k · KV q4_0";
        short = "R 2×128k"; vramEst = "~22 GB"; ctx = 262144; slots = 2; kv = "q4_0";   # -c is the TOTAL, split across slots: -c 131072 -np 2 gave n_ctx 65536 per slot, 19.1 GB (measured 2026-10-14)
      };
      # Qwen3.5-9B abliterated: 512k with YaRN x2 (card: 262,144 native, up to
      # 1,010,000). Its OWN patched template (Qwen3.5's raises on a non-first
      # system message like 3.8's, but it is a different template: no
      # reasoning_effort variable, so --reasoning-effort does nothing here).
      # KV 32 KB/token f16 (8 full-attention layers). Spec from the NAS session 2026-10-14.
      # MEASURED 2026-10-14: 20.6 GB, load 4.6 s, 77 tok/s; mid-turn system message
      # 200 on /v1/messages; needle test at 411,734 tokens: 3/3 exact, prefill
      # 292 s (1,409 tok/s), generation 28.5 tok/s at that context.
      reasoner-9b-512k = {
        label = "Reasoner Qwen3.5-9B abliterated · 1×512k (YaRN ×2) · KV q8_0 · vision";
        short = "R9 512k"; vramEst = "20.6 GB"; ctx = 524288; slots = 1; kv = "q8_0";
        model = "Huihui-Qwen3.5-9B-abliterated.Q8_0.gguf";
        alias = "reasoner-9b-512k";
        template = ../system/app/llama-server/templates/qwen3.5-system-anywhere.jinja;
        extra = [ "--jinja" "--temp" "1.0" "--top-p" "0.95" "--top-k" "20" "--min-p" "0.0" "--presence-penalty" "1.5"
                  "-fa" "on" "--reasoning-budget" "16384"
                  "--rope-scaling" "yarn" "--rope-scale" "2" "--yarn-orig-ctx" "262144"
                  "--mmproj" "/var/lib/llama-server/models/Huihui-Qwen3.5-9B-abliterated.mmproj-Q8_0.gguf" ];
      };
      coder = {
        label = "Coder Qwen3.6-35B-A3B (MoE) · 1×256k · KV q8_0";
        short = "Coder"; vramEst = "20.3 GB"; ctx = 262144; slots = 1; kv = "q8_0";
        model = "Qwen3.6-35B-A3B-UD-IQ4_XS.gguf";   # unsloth, 17.7 GB
        alias = "qwen3.6-35b-a3b";
        template = null;                           # the GGUF's own (OpenCode only; Claude Code needs the system-anywhere fix)
        extra = [ "--jinja" "--temp" "0.6" "--top-p" "0.95" "--top-k" "20" "--min-p" "0.0" "-fa" "on" ];   # model card: thinking mode, precise coding
      };
      # REA M4 (AINF-408): LLM4Decompile-Ref 9B v2 (MIT) — Ghidra pseudo-code -> readable C,
      # an annotation for the RE agent, never ground truth. Same model as DESK's Ollama
      # `llm4decompile-9b` (Q6_K there, 16 GB card); rea-llm-mcp uses whichever is up.
      # Raw /v1/completions with the paper's prompt: no chat template, greedy decoding.
      llm4decompile = {
        label = "LLM4Decompile-Ref 9B v2 Q8_0 · pseudo-code → C (REA)";
        short = "🔧 l4d"; vramEst = "10.6 GB"; ctx = 16384; slots = 1; kv = "";   # MEASURED 2026-10-14: 10640 MB, 1.5 s/function
        model = "llm4decompile-9b-v2.Q8_0.gguf";   # mradermacher; sha256 04d6d7297c220bbfae03a0cade4f1394696f797739df848b43e1c524d188760d (= HF LFS oid, checked 2026-10-15)
        alias = "llm4decompile-9b";
        template = null;
        extra = [ "--temp" "0" "-fa" "on" ];
      };
    } // (let
      # Decision models (System One API, POST /v1/systemone: state + typed
      # questions -> probabilities; chat completions return 501). The pinned
      # image b11580 contains llama.cpp PRs #29818 (systemone), #29831 (Clef)
      # and #29969 (Clef vision). Single forward passes: KV size is irrelevant
      # (f16), no chat template, none of the reasoner's sampling. The whole
      # prompt must fit ONE ubatch (default 512 rejects longer inputs), hence
      # -ub/-b 4096. Requested by Diego via the NAS session 2026-10-14.
      # MEASURED 2026-10-14 (switch + /v1/systemone smoke tests, all pass;
      # Clef fits at -ub 4096): laya 1.0 GB load 2.9 s 0.15 s/req; kev-9b
      # 13.2 GB 4.1 s 0.18 s; decider 17.5 GB 13.4 s 0.40 s text / 0.48 s
      # image; clef 20.1 GB 17.4 s 0.60 s text / 0.25 s image.
      decision = { kind = "decision"; ctx = 16384; slots = 1; kv = ""; template = null; };
      mm = f: [ "--mmproj" "/var/lib/llama-server/models/${f}" ];
      batch = [ "-ub" "4096" "-b" "4096" "-fa" "on" ];
    in {
      decider = decision // {
        label = "Decider pplx-decider v1.1 27B (Artemis GGUF) · vision · decisions";
        short = "⚖ decider"; vramEst = "17.5 GB"; alias = "decider";
        model = "pplx-decider-27B-Artemis-15.3GB.gguf";
        extra = batch ++ mm "mmproj-pplx-decider-27B-Q8_0.gguf";
      };
      clef = decision // {
        label = "Clef 27B Q4_K_M (Cloudflare) · vision · decisions";
        short = "⚖ clef"; vramEst = "20.1 GB"; alias = "clef";
        model = "Clef-Q4_K_M.gguf";   # OOM fallback: Clef-Flash-Q8_0.gguf (9.66 GB, not downloaded)
        extra = batch ++ mm "mmproj-Clef-Q8_0.gguf";
      };
      laya = decision // {
        label = "Laya (ModernBERT-large 421M) · text · decisions";
        short = "⚖ laya"; vramEst = "1.0 GB"; alias = "laya"; ctx = 512;   # 512-token window
        model = "Laya-BF16.gguf";
        extra = batch;
      };
      kev-9b = decision // {
        label = "Kev-9B Q8_0 (Qwen3.5-9B base) · text · decisions";
        short = "⚖ kev-9b"; vramEst = "13.2 GB"; alias = "kev-9b";
        model = "Kev-9B-Q8_0.gguf";
        extra = batch;
      };
    });

    # ============================================================================
    # HEADLESS SERVER — disable GUI/desktop features
    # ============================================================================
    fonts = [ ];
    grafanaEnable = false;
    gpuMonitoringEnable = false;
    kernelModules = [ ];
    fuseAllowOther = false;
    pkiCertificates = [ ];
    polkitEnable = false;
    sddmEnable = false;
    greetdEnable = false;
    servicePrinting = false;
    networkPrinters = false;

    # ============================================================================
    # POWER MANAGEMENT — S3 suspend/wake schedule
    # ============================================================================
    # TLP/power-profiles disabled — custom S3 sleep via systemd timers
    TLP_ENABLE = false;
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    # S3 suspend at 23:00, RTC wake at 16:00 — configured in NAS-specific module
    # (see system/app/nas-services.nix suspend/resume services)
    powerKey = "suspend"; # Physical power button triggers S3 sleep (same as TrueNAS did)

    # ============================================================================
    # NETWORK — LACP bond + VLAN 100 + LAN fallback
    # ============================================================================
    useNetworkd = true;
    networkManager = false;
    resolvedEnable = false;
    nameServers = [ "192.168.20.1" "1.1.1.1" ]; # VLAN router + Cloudflare
    wifiPowerSave = false;

    # LACP Bond (2x Intel X520 10GbE SFP+)
    # Note: VLAN 100 is tagged at the switch, not on the host.
    # Bond0 gets 192.168.20.200 directly (same as TrueNAS config).
    networkBondingEnable = true;
    networkBondingMode = "802.3ad";
    networkBondingInterfaces = [ "tengbe0" "tengbe1" ];
    networkBondingInterfaceMacs = { tengbe0 = "90:e2:ba:86:a2:a0"; tengbe1 = "90:e2:ba:86:a2:a1"; }; # X520 ports
    networkBondingDhcp = false;
    networkBondingLacpRate = "slow"; # TODO: switch to "fast" after confirming Unifi switch LAG is in fast mode
    networkBondingRingBufferSize = 8192; # Max for Intel X520 — prevents rx_missed_errors (NIC-001 from TrueNAS audit)
    networkBondingXmitHashPolicy = "layer3+4";
    networkBondingStaticIp = {
      address = "192.168.20.200/24";
      gateway = "192.168.20.1";
    };

    # Firewall
    firewall = true;
    allowedTCPPorts = [
      22    # SSH
      111   # NFS portmapper
      2049  # NFS
      4000  # NFS statd
      4001  # NFS lockd
      4002  # NFS mountd
      8085  # qBittorrent WebUI
      80    # NPM HTTP
      443   # NPM HTTPS
      81    # NPM admin
      8096  # Jellyfin
      8989  # Sonarr
      7878  # Radarr
      6767  # Bazarr
      9696  # Prowlarr
      5055  # Jellyseerr
      9100  # Node exporter
      8081  # cAdvisor
      6881  # qBittorrent torrent
      9707  # Exportarr sonarr
      9708  # Exportarr radarr
      9709  # Exportarr prowlarr
      9710  # Exportarr bazarr
      8191  # Solvearr (captcha solver)
    ];
    allowedUDPPorts = [
      111   # NFS
      4000  # NFS statd
      4001  # NFS lockd
      4002  # NFS mountd
      6881  # qBittorrent torrent
    ];

    # ============================================================================
    # NAS SERVICES — ZFS, SMART, NFS tuning, S3 sleep, Docker auto-start
    # ============================================================================
    nasServicesEnable = true;
    prometheusHostHealthEnable = true; # docker rootful/rootless up + failed units -> host_health.prom (AINF-368)
    infraNotifyEnable = true; infraNodeName = "nas"; infraBotUrl = "http://100.64.0.6:8765"; # deploy announcements (AINF-368)
    infraRestartEnable = true; # bot's /restart docker-rootless|docker-rootful via ssh + sudo -n (AINF-368 F4)
    # Infra Alerts bot identity for infra-notify (direct Telegram transport; relay is the fallback)
    grafanaTelegramBotToken = secrets.grafanaTelegramBotToken or "";
    grafanaTelegramChatId = secrets.grafanaTelegramChatId or "";
    infraTelegramDeploysThreadId = secrets.infraTelegramDeploysThreadId or "";
    nasZfsPools = [ "ssdpool" "extpool" ];
    # Every dataset nixos-generate-config puts in fstab (keep in sync with `zfs list`)
    nasZfsMountPoints = [
      "/mnt/ssdpool"
      "/mnt/ssdpool/docker"
      "/mnt/ssdpool/media"
      "/mnt/ssdpool/vps-backups"
      "/mnt/ssdpool/workstation_backups"
      "/mnt/extpool"
      "/mnt/extpool/vps-backups"
    ];
    nasHostId = "47bff07a";
    # Trees the VPS backup puller reads over plain ssh as akunito, but which a
    # rootless container owns (AkuCraft writes level.dat / playerdata as uid
    # 100999 mode 0600). nas-backup-acl grants akunito read via POSIX ACL, plus a
    # default ACL so the files the servers create later stay readable.
    nasBackupAclPaths = [
      "/mnt/ssdpool/docker/compose/gameservers"
      # State of the on-demand stacks (AINF-401): mariadb/mongo/CWA write as subuids.
      "/mnt/ssdpool/docker/calibre"
      "/mnt/ssdpool/docker/romm"
      "/mnt/ssdpool/docker/unifi"
    ];
    nasAutoSnapshotEnable = true;
    # tailscale = subnet router for 192.168.8/20 → Headscale, cloudflared = tunnel. Until
    # 2026-10-14 both only lived through `restart: unless-stopped`; a `compose down`
    # (migration cut) removed them and nothing brought them back after the reboot.
    nasRootDockerProjects = [ "vpn-media" "tailscale" "cloudflared" ];
    nasRootlessDockerProjects = [ "npm" "cloudflared" "media" "exporters" "monitoring" ];
    # Stopped by default, started with `nas-svc start <name>` (AINF-401). State lives
    # in /mnt/ssdpool/docker/<name>, NOT under compose/: the VPS "configs" backup job
    # sweeps the whole compose dir except gameservers/.
    nasOnDemandDockerProjects = [
      "calibre"
      "romm"
      "unifi"
      "gameservers/akucraft-survival"
      "gameservers/akucraft-solo"
      "gameservers/akucraft-creative"
      "gameservers/akucraft-staging"
    ];

    # ============================================================================
    # NFS SERVER — exports for DESK, LAPTOP_X13, VPS, DESK_A, DESK_W11
    # DESK_A (Aga's desktop, WiFi) has no route to the storage VLAN and reaches the
    # NAS over Tailscale (source = its tailnet IP 100.64.0.11), so it's listed by
    # that IP rather than a LAN address.
    # DESK_W11 (NixOS-WSL on the DESK box) is the same case: on Windows the Intel
    # X520 that would carry VLAN 100 gets no traffic from the switch, so there is
    # no storage-VLAN address. It mounts the NAS by its TAILNET address
    # (100.64.0.1), which keeps the client's source as its own tailnet IP
    # 100.64.0.15. Mounting 192.168.20.200 instead would go through the pfSense
    # subnet router, which SNATs to 192.168.20.1 — measured — and authorising that
    # would open the export to every device routing through pfSense.
    # ============================================================================
    nfsServerEnable = true;
    nfsExports = ''
      /mnt/ssdpool/media                192.168.20.0/24(rw,sync,insecure,no_subtree_check) 192.168.8.0/24(rw,sync,insecure,no_subtree_check) 100.64.0.8(rw,sync,insecure,no_subtree_check) 100.64.0.15(rw,sync,insecure,no_subtree_check)   # X13 (.8) and DESK_W11 (.15) over Tailscale: they are on 192.168.8.x and the storage VLAN is firewalled from there
      /mnt/ssdpool/workstation_backups  192.168.8.96(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 192.168.8.92(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 192.168.20.96(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.11(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.4(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.8(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.15(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.16(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check)
      /mnt/extpool/downloads            192.168.20.0/24(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 192.168.8.0/24(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.8(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check) 100.64.0.15(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check)
    '';

    # ============================================================================
    # SERVICES
    # ============================================================================
    # GitHub PAT: lifts the anonymous rate limit on flake-input fetches.
    # homelab/base.nix used to read secrets.githubAccessToken directly into
    # nix.extraOptions (i.e. into the world-readable /etc/nix/nix.conf). It now
    # goes through system/security/nix-access-token.nix, which gates on this
    # flag and writes a 0600 per-user nix.conf instead — so the flag has to be
    # set here or the machine silently falls back to anonymous fetches.
    githubAccessToken = secrets.githubAccessToken;
    # Pull prebuilt paths from DESK's harmonia cache before cache.nixos.org
    # (priority 30 vs 40). Reachable over Tailscale, so it works off-LAN too.
    # Extra substituter only — cache.nixos.org stays, and fallback +
    # connect-timeout mean a sleeping DESK costs seconds, never a failed build.
    # DESK (NixOS) and DESK_W11 (same box booted into Windows) — whichever is up
    # serves; scripts/warm-binary-caches.sh drops the one that does not answer.
    nixBinaryCacheSubstituters = [ "http://100.64.0.5:5000" "http://100.64.0.15:5000" ];
    nixBinaryCachePublicKeys = [
      "nixosaku-1:a1t91oU1udPpLWvLr8lWwj2kS5a7lPxhH38p094Ps+s="
      "nixosw11aku-1:AvlQDaw4z34O5P0zgBMmXJKdFN7D4uv/82hCXTWsVqM="
    ];
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${secrets.headscaleDomain}";
    # Advertise same subnets as TrueNAS Docker Tailscale did
    tailscaleAdvertiseRoutes = [ "192.168.8.0/24" "192.168.20.0/24" ];
    havegedEnable = false;
    fail2banEnable = true;
    claudeCodeEnable = true; # Claude Code CLI for remote management

    # Docker — rootless, managed via docker-compose on ssdpool
    # (Compose files at /mnt/ssdpool/docker/compose/)

    # ============================================================================
    # SSH
    # ============================================================================
    sshPort = 22;
    sshHardenEnable = true; # Strict SSH: modern ciphers, auth limits, timeouts
    sshAgentSudoEnable = true; # Passwordless sudo via forwarded SSH agent (matches VPS pattern)
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIErY0vLODupjDrteqGt3SuNW7neUD/ig7lkMiatcmHOU vps-restic-to-truenas" # VPS_PROD restic backups (sftp to extpool/vps-backups)
      # VPS_PROD main key: the akucraft bot (runs on the VPS as a systemd
      # service, no agent) reaches the NAS game servers over BatchMode ssh for
      # health/idle-stop//start//stop. Without this the bot silently saw every
      # NAS server as "absent" and the 45-min idle timer never fired (creative
      # ran for 2 days straight, found 2026-08-25).
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICLo+cGyNOJQCaT2YmfJGUbebNetz0eI4RmB5Yfn2eca akunito@vps-prod" # VPS_PROD akucraft bot -> NAS game servers
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIkhQOHvPAXzA41MYcRBC6Vnv15FDgaFljWVrXoSwk1t akunito@DESK_W11" # DESK_W11 (NixOS-WSL on the DESK box)
    ];

    # ============================================================================
    # SWAP
    # ============================================================================
    swapFileEnable = true;
    swapFileSyzeGB = 8;

    # ============================================================================
    # SOFTWARE FLAGS
    # ============================================================================
    systemBasicToolsEnable = true;
    systemNetworkToolsEnable = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    starCitizenModules = false;

    # System packages
    systemPackages =
      pkgs: pkgs-unstable: with pkgs; [
        btop
        ethtool # Required for NIC ring buffer tuning (bond-ring-buffers service)
        fzf
        p7zip
        smartmontools
        lm_sensors
        usbutils
        pciutils
        git-crypt
        python3 # Required by autoSystemUpdate.sh autofs/NFS scrub step
        restic # security.wrappers.restic points at /run/current-system/sw/bin/restic; the VPS repos in extpool/vps-backups are restored/pruned locally (AINF-401)
      ];

    # ============================================================================
    # AUTO-UPGRADE — stable, weekly
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 12:05:00"; # During wake hours (11-23)
    autoUpgradeRestartDocker = true;
    autoUserUpdateBranch = "release-25.11";

    systemStable = true; # NAS uses stable channel
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "";
    dotfilesDir = "/home/akunito/.dotfiles";
    extraGroups = [
      "wheel"
      "docker" # For root Docker (vpn-media)
      "render" # For Jellyfin GPU access (rootless)
      "video"  # For Jellyfin GPU access (rootless)
    ];

    theme = "io";
    wm = "none";
    wmEnableHyprland = false;

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "";
    defaultRoamDir = "Personal.p";
    term = "";
    font = "";

    dockerEnable = true; # Root Docker for vpn-media (gluetun needs NET_ADMIN)
    dockerRootlessEnable = true; # Rootless Docker for media, npm, cloudflared, exporters, monitoring
    virtualizationEnable = false;

    # Minimal user packages
    userBasicPkgsEnable = false;
    userAiPkgsEnable = false;

    homePackages =
      pkgs: pkgs-unstable: with pkgs; [
        # Headless NAS — minimal
      ];

    zshinitContent = ''
      bindkey '\e[1~' beginning-of-line
      bindkey '\e[4~' end-of-line
      bindkey '\e[3~' delete-char

      PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{cyan}NAS%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';

    sshExtraConfig = ''
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes
    '';
  };
}
