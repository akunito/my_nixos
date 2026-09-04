# DESK Profile Configuration
# Only profile-specific overrides - defaults are in lib/defaults.nix
# Note: Package lists will be evaluated in flake-base.nix where pkgs is available

let
  # Import secrets for database credentials
  secrets = import ../secrets/domains.nix;

  # Starship enable flag (used in zshinitContent)
  starshipEnable = true;

  monitors = {
    samsungMain = {
      criteria = "Samsung Electric Company Odyssey G70NC H1AK500000";
      mode = "3840x2160@120.000Hz";
      scale = 1.6;
    };
    nslVertical = {
      criteria = "NSL RGB-27QHDS    Unknown";
      mode = "2560x1440@144.000Hz";
      scale = 1.25;
      # kanshi transform 270 => Sway reports transform 90 (desired)
      transform = "270";
    };
    philipsTv = {
      criteria = "Philips Consumer Electronics Company PHILIPS FTV 0x01010101";
      mode = "1920x1080@60.000Hz";
      scale = 1.0;
    };
    bnqLeft = {
      criteria = "BNQ ZOWIE XL LCD 7CK03588SL0";
      mode = "1920x1080@60.000Hz";
      scale = 1.0;
    };
  };
in
{
  # Flag to use rust-overlay
  useRustOverlay = false;

  systemSettings = {
    hostname = "nixosaku";
    profile = "personal";
    envProfile = "DESK"; # Environment profile for Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK -s -u";
    gpuType = "amd";
    enableDesktopPerformance = true; # Enable desktop-optimized I/O scheduler and performance tuning
    amdLACTdriverEnable = true;
    amdgpuSuspendWorkaround = true; # AINF-282: kernel 6.17→7.0+ SMU suspend regression on Navi 48
    amdgpuDisableIps = true; # DMCUB wedged on resume 2026-08-07 (INBOX0 HW Lock Ack flood → ~1 FPS desktop)
    # Loose backstop only — the actual fix is the amdgpu_evict_gtt drain in
    # amdgpu-suspend-workaround.nix. Kernel default here is ~15.6 GiB (half of
    # RAM); unbounded, suspend/resume stranding pushed GTT to 9.4 GiB and the
    # suspend-time eviction OOM'd, taking two NVMe controllers down (2026-08-20).
    # Was 6144, but that ran to 85% within 5 suspends and would squeeze the local
    # LLM, which spills ~3.9 GiB into GTT when VRAM is full. 10 GiB leaves the
    # model room while still bounding a runaway.
    amdgpuGttSizeMiB = 10240;
    # Watch the GTT ratchet stay fixed. Regression signature: gtt_used climbing
    # across resumes while vram_used stays low.
    #   journalctl -u gpu-mem-sampler -o cat --since "3 days ago"
    gpuMemSamplerEnable = true;

    # Display Manager Configuration
    greetdEnable = false;
    sddmEnable = true;

    # Keyboard: US International WITH DEAD KEYS (not altgr-intl).
    # Accents on the same key, no AltGr: ' then a = á, " then u = ü, ~ then n = ñ.
    # ' " ` ^ ~ are dead keys: for a literal one type the key then SPACE
    # (e.g. let's = l e t ' space s). ' + s/c/n/z compose Polish ś/ć/ń/ź, so the
    # space is required for apostrophes too. es/pl kept as switchable fallbacks.
    swayKeyboardLayouts = [
      "us(intl)"
      "es"
      "pl"
    ];

    # Shell features
    atuinAutoSync = true; # Enable Atuin cloud sync for shell history
    nextcloudEnable = true; # To startup with Sway daemon
    nextcloudUrl = "https://nextcloud.local.akunito.com"; # public host is behind Cloudflare Access, which no native client can pass
    goaCalendarEnable = true; # GNOME Online Accounts + gnome-calendar + Waybar widget (click opens calendar.google.com in the default browser)
    claudeBackupToNextcloudEnable = true;
    nextcloudSyncFolder = "/home/akunito/Nextcloud";

    # i2c modules removed - add back if needed for lm-sensors/OpenRGB/ddcutil
    kernelModules = [
      "xpadneo" # xbox controller
      "hid_nintendo" # Joy-Con controller
    ];

    # ========================================================================
    # Local Nix binary cache (harmonia) — DESK serves the fleet
    # ========================================================================
    # The laptops and servers were each rebuilding identical closures from
    # source (X13, 62 commits behind, spent ~an hour on bitwarden-desktop,
    # nextcloud-client and voxtype). DESK has the fastest CPU and has usually
    # built them already, so it publishes its store as a substituter.
    #
    # Reachable over tailscale0 (works for laptops off-site) and over the 10GbE
    # bond for full-speed LAN pulls. NOT exposed publicly — the store is a read
    # surface, and store paths are exactly where credentials used to leak from.
    #
    # DESK suspends; clients set fallback + a short connect-timeout so a
    # sleeping cache costs seconds, not a hung rebuild.
    nixBinaryCacheServeEnable = true;
    nixBinaryCacheLanInterfaces = [ "bond0" "eno1" ];

    # Btrfs scrub — both / and /home are btrfs on LUKS and had never been scrubbed.
    btrfsAutoScrubEnable = true;
    btrfsAutoScrubInterval = "monthly";
    btrfsAutoScrubFileSystems = [ "/" "/home" ];

    # Security
    fuseAllowOther = true;
    pkiCertificates = [ /home/akunito/.myCA/ca.cert.pem ];
    # GUI askpass: popup password dialog when sudo has no terminal (e.g., Claude Code)
    sudoAskpassEnable = true;
    sudoTimestampTimeoutMinutes = 180;

    # Polkit
    polkitEnable = true;
    polkitRules = ''
      polkit.addRule(function(action, subject) {
        if (
          subject.isInGroup("users") && (
            // Allow reboot and power-off actions
            action.id == "org.freedesktop.login1.reboot" ||
            action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
            action.id == "org.freedesktop.login1.power-off" ||
            action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
            action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.logout" ||
            action.id == "org.freedesktop.login1.logout-multiple-sessions" ||

            // Allow managing specific systemd units
            (action.id == "org.freedesktop.systemd1.manage-units" &&
              action.lookup("verb") == "start" &&
              action.lookup("unit") == "mnt-NFS_Backups.mount")

            // REMOVED: passwordless policykit.exec for rsync/restic.
            // Both run as root with arbitrary paths, so that rule handed every
            // member of the "users" group a silent root-equivalent primitive
            // (rsync can overwrite /etc; restic's rclone backend executes an
            // arbitrary program). Backups don't need it — they use the
            // security.wrappers.restic capability binary instead.
          )
        ) {
          return polkit.Result.YES;
        }
      });
    '';

    # Backups
    homeBackupEnable = true;
    homeBackupCallNextEnabled = false;
    nfsBackupEnable = true;
    # The NAS S3-suspends at 23:00 and RTC-wakes at 16:00 (see NAS_PROD-config.nix).
    # The default "0/6:00:00" fires at 00:00/06:00/12:00/18:00, so three of the
    # four daily runs landed inside the sleep window and failed by construction —
    # backup-manager.sh has no wake step, it just reports "NFS not accessible"
    # and leaves home_backup.service + mnt-NFS_Backups.mount in a failed state.
    # Run inside the awake window instead, so a failure now means something real.
    homeBackupOnCalendar = "*-*-* 17,21:00:00";

    # Network
    ipAddress = "192.168.8.96";
    wifiIpAddress = "192.168.8.98";
    nameServers = [
      "192.168.8.1"
      "192.168.8.1"
    ];
    resolvedEnable = false;

    # ========================================================================
    # Network Bonding (10GbE LACP aggregation)
    # ========================================================================
    # Hardware: 2x Intel 82599ES 10GbE NICs (enp11s0f0, enp11s0f1)
    # Switch: USW Aggregation (192.168.8.180), SFP+ ports 7-8 in LACP LAG
    # Result: 20Gbps aggregate bandwidth + automatic failover
    #
    # TO DISABLE (e.g., when copying profile to different hardware):
    #   Set networkBondingEnable = false; (all other options ignored)
    #
    # Prerequisites before enabling:
    #   1. Configure LAG/LACP on switch for both ports
    #   2. Verify interface names: ip link show
    #   3. Reserve IP in pfSense DHCP (or use static IP)
    #
    # See: docs/akunito/system-modules/network-bonding.md
    networkBondingEnable = true;
    networkBondingMode = "802.3ad"; # LACP (requires switch support)
    networkBondingInterfaces = [ "enp11s0f0" "enp11s0f1" ];
    networkBondingDhcp = true; # Get IP from pfSense DHCP (see networkBondingMacAddress below: the ".96 reserved" claim does not hold in practice)
    networkBondingVlans = [
      { id = 100; name = "storage"; address = "192.168.20.96/24"; }
    ];
    networkBondingRingBufferSize = 8192; # Max NIC ring buffers for 10GbE (prevents rx_missed_errors)
    # Without this the bond came up with a random MAC (9a:79:1b:40:9e:6a), so the
    # DHCP client-id changed on every recreate and pfSense handed out a different
    # address -- bond0 sat on .97 for days, then flipped to .96 on 2026-09-02,
    # killing every open connection (a browser tab lost its session that way).
    # Pin it to enp11s0f0's permanent MAC so the client-id -- and therefore the
    # lease -- stops moving. Applied 2026-09-02: client-id is now
    # 01:90:e2:ba:a5:69:84 and the bond came up on .97, NOT the .96 this profile
    # claims is reserved, because .96 was still leased to the old random MAC
    # (2 h TTL). Stability was the point and that is achieved; if .96
    # specifically is wanted, add a pfSense static mapping for this MAC.
    networkBondingMacAddress = "90:e2:ba:a5:69:84";

    # ========================================================================
    # Wake-on-LAN (onboard 2.5GbE eno1 — woken by pfSense magic packet)
    # ========================================================================
    # The 10GbE X520 bond has NO WoL; only the onboard Realtek 2.5GbE (eno1)
    # supports it. It MUST keep an IP: with an IP-less (method=disabled) NM
    # connection the NIC doesn't retain its WoL-armed state through S3, so the
    # magic packet no longer wakes DESK (WoL proven working WITH .99 on
    # 2026-07-09, failed IP-less on 2026-07-10). The dual-homing ARP flux that
    # an IP on bond0's subnet caused is fixed instead by arp_ignore/arp_announce
    # sysctls in system/hardware/wol.nix — so we keep .99 and avoid the flux.
    wolEnable = true;
    wolInterface = "eno1";
    wolStaticIp = "192.168.8.99/24"; # needed for WoL to survive suspend; flux handled by arp sysctls
    # eno1 dropped carrier 34 times in 7 days (the X520 bond: 0). Each drop makes
    # tailscaled rebind and tear down the DERP tunnel, which times players out of
    # long-lived sessions (Minecraft, SSH) that ride bond0 and never touch eno1.
    # EEE is the classic r8169 flapper, and the PHY kept renegotiating 2500baseT
    # against a switch port that only offers 1G — so turn EEE off and pin 1G.
    wolDisableEee = true;
    wolAdvertise = "0x020"; # 1000baseT/Full only

    # ========================================================================
    # Local LLM inference server (llama.cpp Vulkan on RX 9070 XT, 16GB)
    # ========================================================================
    # OpenAI-compatible endpoint, Tailscale-only (100.64.0.5), for VPS/NAS apps.
    # Socket-activated: loads on first connection, auto-stops after idle so it
    # doesn't hold ~14GB VRAM during gaming. Swap model via HfRepo.
    # Backend swapped to Ollama 2026-08-21 so SecondBrain's NPCs have an API to
    # talk to (see system/app/ollama-server.nix for why that forces the choice).
    # Rollback is these two lines: true here, false below.
    llamaServerEnable = false;
    llamaServerHost = "0.0.0.0"; # firewalled to tailscale0 only
    llamaServerPort = 8090;
    llamaServerIdleTimeout = "15min"; # free VRAM 15 min after last request
    # Sized so gaming and inference COEXIST. Measured on this card 2026-08-17:
    #   card total ................ 16304 MiB
    #   one Minecraft client ....... 2060 MiB
    #   gpt-oss-20b @ ctx 8192 .... 11275 MiB  <- 12 GB of weights, the floor
    #   GLM-4.6V-Flash Q4 .......... ~6500 MiB
    # gpt-oss-20b left under 3 GB spare with one client and nothing for a spike,
    # and context is not the lever: halving ctx from 16384 only saved 200 MiB
    # because the weights dominate. A smaller model is the only way down.
    #
    # GLM-4.6V-Flash Q4 was tried here to buy that headroom (8200 MiB, leaving
    # 6 GB free) and REVERTED: it is a reasoning model, it reasons in Chinese,
    # and it spent 461 completion tokens producing a five-word villager line.
    # At max_tokens=120 it returned finish_reason=length and EMPTY content -
    # and MCA chooses that budget, not us, so the failure mode is mute
    # villagers. gpt-oss-20b answered the same prompt at max_tokens=200 in
    # 1.15s. Costing 3 GB more for replies that actually arrive is the right
    # trade. A smaller model is still worth having, but it has to be one that
    # does not think before speaking.
    llamaServerModelHfRepo = "ggml-org/gpt-oss-20b-GGUF";
    llamaServerModelHfFile = "";   # quant TAG when set (e.g. "Q4_K_M"), NOT a filename
    # 8192 is plenty: villager turns are short, and /ask (the ~5k-token prompt)
    # does not come here.
    llamaServerCtxSize = 8192;
    # 5 GiB is the correct ceiling for THIS model: 16304 - 11275 = 5029 MiB is
    # exactly what is left for everything else, so loading above that would
    # overcommit the card. It must move with the model, not independently.
    llamaServerVramBusyBytes = 5368709120;

    # === Local LLM — Ollama (active backend) ===
    ollamaServerEnable = true;
    ollamaServerPort = 8090;      # same port llama-server used; nothing upstream changes
    ollamaServerKeepAlive = "15m";
    # 32768, raised from 8192 on 2026-09-02. The old value was sized for villager
    # turns and it made gpt-oss UNUSABLE as a coding agent: OpenCode's system
    # prompt alone reached 7282 tokens against an 8192 window, so the agent loop
    # never converged — measured as a run that hung for ten minutes emitting task
    # after task.
    #
    # The rise is nearly free on this model. gpt-oss uses sliding-window
    # attention on alternating layers, so 32k costs 786 MiB of KV, and it still
    # loads 25/25 layers with the whole thing on the GPU at 111-113 tok/s
    # (faster than the 106 measured at 8k, because the desktop is leaner now).
    #
    # A separate wide-context COPY of gpt-oss was the obvious alternative and is
    # the wrong shape: OLLAMA_MAX_LOADED_MODELS=1 would make every switch between
    # the villager model and the coding model evict and reload 12 GiB of
    # identical weights. One model with a window big enough for both wins.
    #
    # Only models WITHOUT num_ctx in their Modelfile are affected, so the Qwen
    # entries keep their deliberate 16384 — their KV is 1024 MiB there already,
    # and Gated-DeltaNet or not, doubling it would push them off the card.
    ollamaServerCtxSize = 32768;
    # 0.21.1 (nixpkgs-stable) cannot load Qwen3.8 at all — its hybrid
    # Gated-DeltaNet runtime landed in 0.32.12. Unstable has 0.32.14, which is
    # also the version of the CLI userAiPkgsEnable already puts on this box.
    ollamaServerUseUnstable = true;
    # Vulkan (RADV), not ROCm. Benchmarked here 2026-09-01, 250 tokens x2:
    # qwen3.8-agent 27.4 -> 30.9 tok/s (+13%), gpt-oss:20b 92.4 -> 106.2 (+15%).
    # RADV compiles native GFX1201 shaders where ROCm reaches RDNA4 generically.
    #
    # The speed is the smaller half. ROCm reports free VRAM as if no other
    # process were on the card — it claimed 15.8 GiB free while sysfs showed
    # 10299 MiB — which is what let Ollama overcommit and fault the GPU on
    # 2026-09-01. Vulkan reported 13994 MiB against sysfs's 13994 MiB: exact.
    # An honest number is what lets Ollama decline or offload instead of crash.
    ollamaServerBackend = "vulkan";

    # --- OpenCode: which local models it may drive -------------------------
    # ids must match `curl 127.0.0.1:8090/v1/models` EXACTLY; a wrong name is
    # not a startup error, it is a 404 on the first request.
    #
    # contextLimit is what OpenCode uses to decide when to compact a session, so
    # it must match the model's REAL window, which for us is whatever num_ctx
    # the Modelfile baked in (qwen3.8-agent) or OLLAMA_CONTEXT_LENGTH otherwise
    # (gpt-oss, 8192 — sized for villagers, not for coding). Telling OpenCode a
    # bigger number than the server will honour makes it send prompts the runner
    # silently truncates.
    #
    # For coding, qwen3.8-agent is the better of the two despite being 3.5x
    # slower: 16k of context beats 8k, and a dense 27B reasons better about
    # multi-file edits than gpt-oss's 3.6B active params. gpt-oss stays listed
    # for quick questions where 106 tok/s matters more than depth.
    # outputLimit is the ceiling on ONE reply and must leave room for the prompt
    # inside the same window — half the context is the rule of thumb here. Both
    # keys are mandatory: OpenCode validates the whole config and refuses to
    # start on a partial `limit`, so a missing outputLimit takes every model
    # down, not just its own.
    # IQ3_S is the default because it tolerates a working desktop. The XL entry
    # is faster-per-quality only while the desktop stays under ~1.2 GiB, and the
    # cliff is steep — see the measured curve on the entry itself.
    openCodeDefaultModel = "ollama/qwen3.8-agent";
    openCodeModels = [
      { id = "qwen3.8-agent";    label = "Qwen3.8 27B IQ3_S (16k, safe)";
        contextLimit = 16384; outputLimit = 8192; }
      { id = "qwen3.8-agent-xl"; label = "Qwen3.8 27B Q3_K_XL (16k, quiet desktop)";
        contextLimit = 16384; outputLimit = 8192; }
      { id = "gpt-oss:20b";      label = "gpt-oss 20B (fast, 32k)";
        contextLimit = 32768; outputLimit = 8192; }
    ];
    # One at a time: gpt-oss:20b (~12 GiB) and qwen3.8-agent (~12 GiB) cannot
    # both be resident on a 16 GiB card.
    ollamaServerMaxLoadedModels = 1;
    # 0 — and it MUST be 0 while ollamaServerBackend = "vulkan".
    #
    # This was 2 GiB, sized to cover how far ROCm's free-VRAM figure was from
    # reality. Vulkan does not have that problem (it reported 13994 MiB against
    # sysfs's 13994 MiB), so the reserve became a second, unnecessary deduction
    # on an already-correct number. Measured immediately after the switch:
    # gpt-oss:20b projected 12342 MiB against 9807 MiB "free", so 6713 MiB of
    # weights were mapped to CPU RAM and throughput fell from 106 to 40 tok/s.
    # Restore a non-zero value ONLY if going back to the rocm backend.
    ollamaServerGpuOverheadBytes = 0;
    # Gaming backstop, NOT a fit check. The old 13 GiB floor meant that an
    # ordinary session (2.9 GiB desktop + a 3.9 GiB Minecraft client leaves
    # ~9.5 GiB) refused to start ollama at all, so the villager model went to
    # paid DeepSeek for no reason. Measured 2026-09-01.
    ollamaServerVramNeededBytes = 6442450944;

    # --- Reclaim the desktop's COLD VRAM before a model loads ---
    # SwayFX's scenefx renderer reserves four full-output-size framebuffers per
    # output for blur, and does it whether blur is enabled or not (the only gate
    # is `basic_renderer = (output == NULL)` in scenefx-0.4.1
    # render/fx_renderer/fx_pass.c:1132). On this 3840x2160 + 2560x1440 pair
    # that is ~750 MiB reserved, never read, sitting in the fastest memory on
    # the box. `blur disable` at runtime frees nothing — measured.
    #
    # Measured 2026-09-02: evicting first takes the idle desktop from 1250 to
    # 104 MiB; loading gpt-oss:20b on top then lands at 13053 MiB with sway
    # holding 722 MiB, flat over 45 s of ordinary use. The same load without
    # evicting lands at 13560 MiB. ~500 MiB recovered, nothing thrashing.
    #
    # Ceiling 4 GiB and the resident-model guard in the script are LOAD-BEARING:
    # GTT here is 10240 MiB (amdgpuGttSizeMiB) and a resident model is ~12.4 GiB,
    # so evicting with a model up would ask TTM to push more into GTT than GTT
    # can hold.
    ollamaServerEvictVram = true;
    ollamaServerEvictThresholdBytes = 1073741824;  # 1 GiB — DESK-specific: two monitors (3840x2160 + 2560x1440) put the desktop at ~1.2 GiB and it settles at ~860 MiB after an evict, so a lower floor would fire forever for nothing. A single-screen machine sits under this and stays a no-op, which is correct.
    # EVERYTHING AUTOMATIC IS OFF, and that is the measurement talking, not
    # caution. On a quiescent desktop the eviction takes ~1 s. On an actively
    # rendering one it livelocked for 245 s with the GPU pegged at 98%, VRAM
    # oscillating 461 -> 824 -> 273 MiB as the compositor faulted buffers back
    # in as fast as TTM pushed them out. Nothing bounds that: TimeoutStartSec
    # only stops systemd waiting, the kernel keeps going.
    #
    # So `llama-evict` is a DELIBERATE command — run it on a quiet desktop right
    # before loading a model you want the headroom for. GUARD 5 (gpu_busy) makes
    # it refuse the worst case, but it cannot promise the desktop stays quiet.
    ollamaServerEvictMaxGpuBusyPercent = 10;   # an idle desktop here reads 1-6%
    ollamaServerEvictOnOllamaStart = false;
    ollamaServerEvictTimerSec = 0;
    ollamaServerEvictTimeoutSec = 60;

    # Measure the peak, because the decision rests on it: rounded corners are
    # worth giving up ONLY if the reclaimed VRAM is enough to move Qwen3.8 from
    # UD-IQ3_S (12.04 GB) up to UD-Q3_K_XL (13.15 GB). That needs the desktop to
    # PEAK under ~2.7 GiB, not to idle under it. Leave this running across a
    # relogin into each compositor and compare with `vram-report`.
    vramSamplerEnable = true;

    # --- Second model: Qwen3.8-27B for agent work (Hermes), on demand ---
    # NOT a replacement for gpt-oss:20b. Different job, different trade:
    # gpt-oss is MoE (~3.6B active) and answers a villager in 1.4-2.0s; this one
    # is a DENSE 27B, so it is much slower per token but far stronger at
    # multi-step agent reasoning. It is expected to be unusable while gaming,
    # which the lock file and the VRAM backstop already handle.
    #
    # Built from a Modelfile because the official qwen3.8:27b tag is 17.74 GB —
    # larger than the whole card. See system/app/ollama-server.nix for the quant
    # ladder and how the size was chosen; UD-IQ3_XXS (10.93 GB) is the fallback
    # if IQ3_S turns out to spill onto the CPU under load.
    ollamaServerCustomModels = [
      { name = "qwen3.8-agent";
        from = "hf.co/unsloth/Qwen3.8-27B-GGUF:UD-IQ3_S";
        parameters = {
          # 16384, not the model's native 262144: context is billed in VRAM and
          # this card has ~1.3 GiB to spare once the weights are in. Agent turns
          # that need more than 16k belong on a hosted model, not this GPU.
          num_ctx = 16384;
          # Qwen's OFFICIAL non-thinking sampling profile. Baked in here because
          # Ollama's /v1 endpoint accepts no top_k at all, so a caller could not
          # set it even if it wanted to.
          temperature = 0.7;
          top_p = 0.8;
          top_k = 20;
          min_p = 0.0;
        };
      }

      # The same model one quant up. NOT a replacement — both stay, and which
      # one you ask for is a decision about the session you are in.
      #
      # Sized against the vram-sampler's measured PEAKS (see the table in
      # docs/handoffs/akunito/2026-09-02-main.md), not a snapshot, because every
      # hand-taken figure in this repo understates the peak by ~25%:
      #
      #   desktop VRAM   min 1636 · median 2359 · p95 2621 · PEAK 4778 (Minecraft)
      #   needs desktop under:  IQ3_S 3892 · Q3_K_XL 2748 · IQ4_XS 1614 MiB
      #
      # Those ceilings are computed from file size and they are OPTIMISTIC.
      # MEASURED 2026-09-02, desktop ~2.4 GiB, nothing else on the card:
      #
      #             projection   free   layers    to CPU    tok/s
      #   IQ3_S       11940     13662    64/66     785      26-27
      #   Q3_K_XL     12994     13730    59/66    1706      14.1
      #
      # Both were projected to fit and neither did: Ollama's breakdown omits the
      # vision/CLIP buffers (the same ~1.2 GiB gap that made an 11928 MiB
      # projection cost 14517 MiB on 2026-09-01), so it loads optimistically and
      # gives the remainder to the CPU.
      #
      # THE CURVE, measured 2026-09-02 by closing apps one at a time. This is the
      # whole decision, and the cliff is the point:
      #
      #   desktop     XL layers  XL tok/s    IQ3_S layers  IQ3_S tok/s
      #   1133 MiB      66/66     33.7-34.1     66/66        ~36
      #   1581 MiB      63/66     20.7-21.2     66/66       35.3-36.3
      #   2480 MiB      59/66     14.1-14.5     64/66        26-27
      #
      # XL is a real option — it matches IQ3_S once fully resident — but only
      # below ~1.2 GiB of desktop, and 450 MiB past that costs it 40% of its
      # speed. IQ3_S holds 66/66 up to ~1.6 GiB and degrades gently. So XL is
      # for a deliberately emptied session (this measurement needed vesktop,
      # VSCode, Obsidian and Chromium all closed) and IQ3_S is the default.
      #
      # Penalty for guessing wrong is a slow answer, not a crash — the crash
      # mode was ROCm's false free-VRAM figure, and we are on Vulkan.
      #
      # `llama-status` prints free VRAM; `llama-evict` recovers ~500 MiB first,
      # but ONLY with no model resident (GTT is 10240 MiB, less than either
      # model) and ONLY on a quiet desktop — it livelocks on a busy one.
      { name = "qwen3.8-agent-xl";
        from = "hf.co/unsloth/Qwen3.8-27B-GGUF:UD-Q3_K_XL";
        parameters = {
          # Identical to the IQ3_S entry on purpose: the two differ ONLY in
          # quantisation, so any speed or quality difference you observe is the
          # quant and not a stray sampling change.
          num_ctx = 16384;
          temperature = 0.7;
          top_p = 0.8;
          top_k = 20;
          min_p = 0.0;
        };
      }
    ];
    # Auth: still OFF, deliberately. The endpoint is tailscale-only + firewalled,
    # and VPS_PROD fronts it with llamaWakeProxyEnable — that proxy forwards
    # requests verbatim, so switching auth on here breaks every app behind it
    # until each one is taught to send the key. To enable, add the key to
    # secrets/domains.nix, set the line below, then update the consumers:
    #   llamaServerApiKeySecret = "llamaServerApiKey";
    # (llamaServerApiKeySecret takes the attribute NAME, so the key stays out of
    # the store and out of `ps` — unlike the legacy llamaServerApiKey option.)
    llamaServerApiKey = "";

    # Firewall
    # NOTE: sunshineEnable = true sets services.sunshine.openFirewall in
    # profiles/work/configuration.nix, which opens 47984/47989/47990/48010 (TCP)
    # and the 47998-48010 UDP range itself — the commented-out entries below are
    # historical, NOT proof that Sunshine is firewalled off. The ports stay open
    # even with sunshineAutoStart off; only the session autostart is gated.
    allowedTCPPorts = [
      9100 # prometheus workstation exporter
      2049 # NFS server (see nfsExports below). Opening the port is not the
           # access control here — /etc/exports is, and it names individual
           # hosts. NFSv4 needs only this one port; the fixed lockd/mountd/statd
           # ports in nfs_server.nix are for v3, which no client here uses.
    ];

    # ========================================================================
    # NFS server — the two Games drives
    # ========================================================================
    # Both live on ntfs3 filesystems mounted uid=1000,gid=1000, so everything
    # in them is already owned by one user; all_squash keeps it that way for
    # whoever writes from another machine.
    #
    # fsid= is not optional here: NFSv4 needs a stable filesystem identity, and
    # NTFS does not give nfsd a UUID to derive one from. Without it the export
    # is refused. The numbers are arbitrary but must stay put — changing one
    # invalidates every file handle a client is holding.
    #
    # Who reaches this machine as what, measured rather than assumed:
    #   X13       arrives on the LAN as 192.168.8.92 (dock) or .91 (wifi), and
    #             as 100.64.0.8 when away. Read-write.
    #   LAPTOP_A  arrives as 100.64.0.4 even though it sits on the same LAN:
    #             it runs with accept-routes on, so pfSense's advertised
    #             192.168.8.0/24 sends its traffic through the tunnel. Exporting
    #             to its LAN address 192.168.8.78 would simply never match.
    #             Read-only.
    nfsServerEnable = true;
    nfsExports = ''
      /mnt/DATA/Games        192.168.8.92(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=11) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=11) 100.64.0.8(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=11) 100.64.0.4(ro,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=11)
      /mnt/DATA_SATA3/Games  192.168.8.92(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=12) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=12) 100.64.0.8(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=12) 100.64.0.4(ro,sync,insecure,all_squash,anonuid=1000,anongid=1000,no_subtree_check,fsid=12)
    '';
    allowedUDPPorts = [
      # 51820 # Wireguard
    ];

    # eno1 (192.168.8.99) and bond0 (192.168.8.97) are both on 192.168.8.0/24,
    # and the route through eno1 has the lower metric. Strict reverse-path
    # filtering therefore dropped everything that arrived on bond0 from a LAN
    # host — silently, in mangle PREROUTING, before any rule that logs. That
    # included Tailscale's LAN discovery probes to bond0, which is the address
    # this machine advertises as its endpoint, so X13 could never build a
    # direct path and fell back to the DERP relay.
    firewallReversePathLoose = true;

    # ========================================================================
    # Docker firewall backstop
    # ========================================================================
    # Published container ports (docker-compose `ports:` defaults to 0.0.0.0)
    # bypass allowedTCPPorts entirely — they are DNAT'd through FORWARD, not
    # INPUT. Without this, the leftyworkout dev/test stacks exposed Postgres
    # 5432/5433, Redis 6380 and the Rails apps to the whole LAN and to every
    # Tailscale peer. Compose files live in project repos, so the block has to
    # happen here.
    dockerFirewallEnable = true;
    dockerFirewallExternalInterfaces = [
      "bond0"      # 10GbE LACP (LAN)
      "bond0.100"  # storage VLAN
      "eno1"       # onboard 2.5GbE (WoL NIC)
      "tailscale0" # mesh peers are NOT a trust boundary for raw DB ports
    ];
    # Exceptions: the dev/test web UIs stay reachable over Tailscale so the
    # phone can hit them for mobile testing. Databases and Redis are NOT listed
    # here on purpose — they stay blocked on every external interface.
    dockerFirewallAllowedPorts = [
      { interface = "tailscale0"; port = 3110; } # leftyworkout backend (dev)
      { interface = "tailscale0"; port = 3111; } # leftyworkout frontend (dev)
      { interface = "tailscale0"; port = 3210; } # leftyworkout backend (dev2)
      { interface = "tailscale0"; port = 3211; } # leftyworkout frontend (dev2)
      { interface = "tailscale0"; port = 6006; } # Storybook (dev)
      { interface = "tailscale0"; port = 6007; } # Storybook (dev2)
    ];

    # Drives
    mount2ndDrives = true;
    disk1_enabled = true;
    disk1_name = "/mnt/2nd_NVME";
    disk1_device = "/dev/mapper/2nd_NVME";
    disk1_fsType = "ext4";
    disk1_options = [
      "nofail"
      "x-systemd.device-timeout=3s"
      "noatime"
      "nodiratime"
    ];
    disk2_enabled = true;
    disk2_name = "/mnt/DATA_SATA3";
    disk2_device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
    disk2_fsType = "ntfs3";
    disk2_options = [
      "nofail"
      "x-systemd.device-timeout=3s"
      "uid=1000"
      "gid=1000"
    ];
    # NFS_media / NFS_Backups / NFS_downloads are declared ONCE, in
    # nfsMounts + nfsAutoMounts below. The disk3/disk8/disk9 slots used to carry
    # duplicate definitions; the bodies are deleted rather than left commented so
    # nobody can flip _enabled back to true and end up with two competing mount
    # units for the same path.
    disk3_enabled = false;
    # disk4 (emulators) and disk5 (library) removed — datasets no longer exist on TrueNAS,
    # data lives on VPS (romm-library, calibre-library). See IAKU-247.
    disk4_enabled = false;
    disk5_enabled = false;
    disk6_enabled = true;
    disk6_name = "/mnt/DATA";
    disk6_device = "/dev/disk/by-uuid/48B8BD48B8BD34F2";
    disk6_fsType = "ntfs3";
    disk6_options = [
      "nofail"
      "x-systemd.device-timeout=3s"
      "force"
      "uid=1000"
      "gid=1000"
    ];
    # Temporarily disabled - device UUID b6be2dd5-d6c0-4839-8656-cb9003347c93 not found
    # NixOS fails to generate systemd mount unit when device doesn't exist, causing build failures
    # Re-enable when device is available or UUID is updated
    disk7_enabled = false;
    # disk7_name = "/mnt/EXT";
    # disk7_device = "/dev/disk/by-uuid/b6be2dd5-d6c0-4839-8656-cb9003347c93";
    # disk7_fsType = "ext4";
    # disk7_options = [ "nofail" "x-systemd.device-timeout=5s" "noatime" "nodiratime" ];
    disk8_enabled = false; # see note at disk3
    disk9_enabled = false; # see note at disk3

    # NFS client
    nfsClientEnable = true;
    nfsMounts = [
      {
        what = "192.168.20.200:/mnt/ssdpool/media";
        where = "/mnt/NFS_media";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,soft,retrans=3,timeo=50";
      }
      # library and emulators NFS mounts removed — datasets no longer exist (IAKU-247)
      {
        what = "192.168.20.200:/mnt/ssdpool/workstation_backups";
        where = "/mnt/NFS_Backups";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,soft,retrans=3,timeo=50";
      }
      {
        what = "192.168.20.200:/mnt/extpool/downloads";
        where = "/mnt/NFS_downloads";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,soft,retrans=3,timeo=50";
      }
    ];
    nfsAutoMounts = [
      {
        where = "/mnt/NFS_media";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      # NFS_library and NFS_emulators automounts removed (IAKU-247)
      {
        where = "/mnt/NFS_Backups";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
      {
        where = "/mnt/NFS_downloads";
        automountConfig = {
          TimeoutIdleSec = "600";
        };
      }
    ];

    # SSH
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # Printer & Scanner
    servicePrinting = true;
    networkPrinters = true;
    serviceScannerEnable = true;

    # Power management
    powerManagement_ENABLE = true;
    power-profiles-daemon_ENABLE = true;
    powerKey = "suspend"; # Power button suspends (overridden by hibernate.nix acpid when UUID is set)

    # Hibernation: on-demand only (no auto suspend-then-hibernate — no battery)
    hibernateEnable = true;
    # LUKS UUID of encrypted swap partition (from: sudo cryptsetup luksDump /dev/nvme1n1p3)
    hibernateSwapLuksUUID = "6439621e-01dc-4710-adb8-8894fc6ce585";

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      pkgs.hdparm # Disk parameter utility (ATA secure erase, etc.)
      pkgs.cameractrls-gtk4 # Webcam control GUI (brightness/focus/PTZ for Logitech C920); CLI v4l2-ctl via v4l-utils below
      pkgs.v4l-utils # v4l2-ctl CLI for scripting camera controls
      # SDDM wallpaper override is automatically added in flake-base.nix for plasma6
    ];

    # === Gaming ===
    freesmLauncherEnable = true; # FreeSM Launcher (Prism fork, offline accounts) — connect to AkuCraft over Tailscale
    akucraftInstances = [ "prod" "staging" "solo" "creative" ]; # this is the machine that owns the private worlds
    # Launch every instance under gamemoderun, so GameMode's hooks take the
    # local-LLM lock while Minecraft runs. Not optional on this box any more:
    # the HD client grew from 2.0 to 3.9 GiB of VRAM with the ULTRA shaders, and
    # 3.9 + 11.9 (gpt-oss) + 2.9 (desktop) does not fit in 16.3 GiB. Sharing the
    # card faults amdgpu and kills the game, measured 2026-09-01.
    #
    # THE TRADE: while you are playing, the local model is off, so MCA villagers
    # answer from DeepSeek (~2.3s, paid) instead of the GPU (~1.5s, free). That
    # is the cost of not crashing. Set false to take the lock off and manage it
    # by hand with llama-lock / llama-unlock.
    freesmLauncherGamemodeWrapper = true;

    # === Webcam controls (Logitech C920) — persist across reboot/hotplug/resume ===
    webcamControlsEnable = true;
    webcamControlsIdVendor = "046d";
    webcamControlsIdProduct = "082d";
    webcamControlsDevice = "/dev/v4l/by-id/usb-046d_HD_Pro_Webcam_C920_D524172F-video-index0";
    webcamControlsSettings = "brightness=136,contrast=35,saturation=128,sharpness=128,gain=194,power_line_frequency=1,white_balance_automatic=1,backlight_compensation=1";

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS - Centralized Control
    # ============================================================================

    # === Package Modules ===
    systemBasicToolsEnable = true; # Basic system tools (vim, wget, rsync, cryptsetup, etc.)
    systemNetworkToolsEnable = true; # Advanced networking tools (nmap, traceroute, dnsutils, etc.)

    # === Desktop Environment & Theming ===
    enableSwayForDESK = false; # Not needed when wm = "sway" (no dual-WM setup)
    stylixEnable = true; # Enable Stylix for system-wide theming
    swwwEnable = true; # Enable swww wallpaper daemon for Sway (robust across reboot + HM rebuilds)
    waypaperEnable = true; # Enable Waypaper GUI wallpaper manager (Hyper+Shift+S)
    swaybgPlusEnable = false; # [DEPRECATED] Use waypaperEnable instead
    swayIdleDisableMonitorPowerOff = true; # Disable monitor power-off (Samsung Odyssey G70NC DPMS wake issue)

    # === Monitor Management (Imperative GUI) ===
    nwgDisplaysEnable = true; # Visual monitor layout GUI (Hyper+Shift+D)
    workspaceGroupsGuiEnable = true; # Workspace groups assignment GUI (Hyper+`)
    kanshiImperativeMode = true; # Use nwg-displays to manage monitors (config in ~/.config/kanshi/config)

    # === System Services & Features ===
    sambaEnable = false; # Samba file sharing disabled (not currently needed)
    sunshineEnable = true; # Enable Sunshine game streaming
    wireguardEnable = true; # Enable WireGuard VPN
    appImageEnable = true; # Enable AppImage support
    gamemodeEnable = true; # Enable GameMode for performance optimization
    xboxControllerEnable = true; # Enable Xbox controller support (xpadneo)
    bluetoothDisableUsbAutosuspend = true; # MT7922 BT: stop USB runtime-suspend killing the HFP mic

    # Fifine K669B sits ~40 cm away, so it picks up the steady hum of DESK, the
    # NAS and the X13. Measured noise floor -48.7 dBFS against a -16.4 dBFS
    # voice peak; RNNoise plus a high-pass cleans that up without a boom arm.
    micNoiseSuppression = {
      target = "alsa_input.usb-0c76_USB_PnP_Audio_Device-00.mono-fallback";
      nodeName = "mic_clean";
      description = "Fifine K669B (clean)";
      highPassHz = 90;
      vadThreshold = 50.0;
    };
    joycondEnable = true; # Enable Joy-Con controller support (joycond daemon)

    # === Tailscale Mesh VPN ===
    tailscaleEnable = true; # Enable daemon (but don't auto-connect - manual via Trayscale GUI)
    trayscaleGuiEnable = true; # Enable GUI tray app with Sway for manual control
    tailscaleLoginServer = "https://${secrets.headscaleDomain}"; # Self-hosted Headscale
    # DESK is always on LAN - override local routes/DNS with Tailscale
    tailscaleAcceptRoutes = false; # Accept routes (already on LAN)
    tailscaleAcceptDns = false; # Don't override DNS (use pfSense directly)

    # === SSH Configuration ===
    sshHostsManaged = true; # Nix-managed ~/.ssh/config (shared SSH host definitions)

    # === Development Tools & AI ===
    developmentToolsEnable = true; # Enable development IDEs and cloud tools
    githubAccessToken = secrets.githubAccessToken; # GitHub PAT: lifts anon rate limit on flake-input fetches
    perplexityApiKey = secrets.perplexityApiKey; # Perplexity API key for Claude Code MCP
    jellyseerrApiKey = secrets.jellyseerrApiKey; # Jellyseerr API key for Claude Code MCP (media requests)
    planeApiToken = secrets.planeApiToken; # Plane API token for Claude Code MCP
    # Internal Tailscale vhost, NOT the public host: plane.<publicDomain> sits
    # behind Cloudflare Access, which rejects at the edge before Plane ever sees
    # the API token — the MCP just gets the Access login page as HTML.
    planeApiUrl = "https://plane.${secrets.wildcardLocal}";
    planeWorkspaceSlug = "akuworkspace";
    grafanaMcpToken = secrets.grafanaMcpToken; # Grafana MCP (read-only dashboards + PromQL)
    grafanaMcpUrl = "https://grafana.${secrets.publicDomain}";
    dbClaudeReadonlyConnStr = "postgresql://claude_readonly:${secrets.dbClaudeReadonlyPassword}@vps-prod:5432/plane";
    n8nMcpApiKey = secrets.n8nApiKey; # n8n MCP (workflow automation)
    n8nMcpUrl = "https://n8n.${secrets.publicDomain}";
    jlOnboardAccessToken = secrets.jlOnboardAccessToken; # jl-onboard MCP (hosted HTTP transport)
    aichatEnable = false; # Enable aichat CLI tool with OpenRouter support
    nixvimEnabled = false; # Enable NixVim configuration (Cursor IDE-like experience)
    lmstudioEnabled = true; # Enable LM Studio configuration and MCP server support
    voxtypeEnable = true; # Enable Voxtype voice dictation (hold Super+V to speak)

    # === Control Panel ===
    controlPanelEnable = false; # Disabled for now (web server) — not in use; re-enable when needed
    controlPanelNativeEnable = true; # Enable NixOS infrastructure control panel (native desktop app)

    # === Monitoring ===
    prometheusWorkstationExporterEnable = true; # Lightweight metrics exporter (update timestamps, disk, backup)

    # === Database Client Credentials ===
    # Generate ~/.pgpass, ~/.my.cnf, ~/.redis-credentials for CLI tools and DBeaver
    dbCredentialsEnable = true;
    dbCredentialsHost = "vps-prod"; # VPS Tailscale hostname
    # NOTE: pass the secret ATTRIBUTE NAME, not the value — the value would be
    # baked into a world-readable /nix/store path. Resolved at activation time.
    dbCredentialsPostgres = [
      { database = "plane"; user = "plane"; passwordSecret = "dbPlanePassword"; }
      { database = "rails_database_prod"; user = "liftcraft"; passwordSecret = "dbLiftcraftPassword"; }
    ];
    dbCredentialsMariadb = [
      { database = "nextcloud"; user = "nextcloud"; passwordSecret = "dbNextcloudPassword"; }
    ];
    dbCredentialsRedisPasswordSecret = "redisServerPassword";

    # === SwayFX vs upstream sway ===
    # ON TRIAL as of 2026-09-02: false = upstream sway 1.11, no blur / rounded
    # corners / shadows / inactive-dim. Coloured focus borders and client-side
    # transparency (kitty + alacritty at 0.85, waybar rgba) are UNAFFECTED —
    # those are upstream features, verified against sway 1.11's command table.
    #
    # Why: scenefx allocates its blur framebuffers per output unconditionally,
    # whether or not any effect is enabled. Measured here — nested, same config,
    # no clients, one output — SwayFX 0.5.3 = 392.6 MiB in 37 BOs vs sway 1.11 =
    # 99.2 MiB in 16. On this 3840x2160 + 2560x1440 pair that is ~890 MiB of the
    # desktop's ~1190 MiB, which is roughly one quantisation step for the local
    # model. Set back to true to get the looks back; it is one line and a
    # relogin. Full reasoning in lib/defaults.nix.
    swayUseSwayfx = false;

    # === Monitor Configuration (Sway/SwayFX) ===
    # Primary monitor for SwayFX: use hardware-ID string to avoid connector drift.
    swayPrimaryMonitor = monitors.samsungMain.criteria;

    # Monitor inventory (data-only); used to build DESK kanshi settings.
    swayMonitorInventory = monitors;

    # Deterministic workspace->output pinning (group N => workspaces N1..N0).
    # Drives the declarative `workspace N output` lines in swayfx-config.nix
    # and the hotplug restore script's group-0 orphan migration.
    swayWorkspaceOutputPins = [
      { criteria = monitors.samsungMain.criteria; group = 1; } # 11-20
      { criteria = monitors.nslVertical.criteria; group = 2; } # 21-30
      { criteria = monitors.philipsTv.criteria;   group = 3; } # 31-40
      { criteria = monitors.bnqLeft.criteria;     group = 4; } # 41-50
    ];

    # Monitor-hotplug snapshot/restore: when monitors are switched off and back
    # on, restore the visible workspace per output, the focused workspace, and
    # floating-window positions (fixes focus jumps + floating windows straddling
    # two monitors after power-off/on). Replaces the focus-fragile legacy
    # swaysome init/rearrange/assign-groups kanshi exec chain.
    swayHotplugRestoreEnable = true;

    # Sway/SwayFX: kanshi output layout (DESK-only).
    # Other profiles keep default behavior by leaving this as null (see lib/defaults.nix).
    #
    # NOTE: Disabled for imperative mode - use nwg-displays (Hyper+Shift+D) to configure
    # Monitor config is saved to ~/.config/kanshi/config
    #
    # NOTE: On this setup, kanshi transform values map inversely to what Sway reports:
    # - kanshi transform "270" => Sway reports transform 90 (desired portrait rotation).
    swayKanshiSettings = null; # Disabled - using imperative nwg-displays instead

    # DEPRECATED declarative config (kept for reference):
    # swayKanshiSettings = [
    #   # If the Philips/TV output is present, enable and configure it.
    #   # NOTE: Ordering matters: kanshi picks the first matching profile.
    #   {
    #     profile = {
    #       name = "desk-tv";
    #       outputs = [
    #         # CRITICAL: Use full hardware IDs as criteria (anti-drift).
    #         # Ordering matters: Samsung is first so swaysome stabilizes Group 1 on it.
    #         (monitors.samsungMain // { position = "0,0"; })
    #         (monitors.nslVertical // { position = "2400,-876"; })
    #
    #         # HDMI-A-1 (Philips): enable at 1920x1080@60 and place to the right of DP-2.
    #         # DP-2 logical width is 1152 (1440 / 1.25) so x = 2400 + 1152 = 3552
    #         # Explicitly enable the output (it may be disabled by the fallback profile).
    #         (
    #           monitors.philipsTv
    #           // {
    #             status = "enable";
    #             position = "3552,-876";
    #           }
    #         )
    #
    #         # BNQ (Group 4 -> workspaces 41-50): enable and place to the LEFT of Samsung.
    #         # Best available mode observed: 1920x1080@60Hz. Keep scale default 1.0.
    #         (
    #           monitors.bnqLeft
    #           // {
    #             status = "enable";
    #             position = "-1920,0";
    #           }
    #         )
    #       ];
    #       # CRITICAL: Initialize swaysome daemon (workspace groups starting at 1).
    #       # Workspace-to-output assignments are now handled declaratively in swayfx-config.nix.
    #       # Restore wallpaper when kanshi applies this profile (monitor connect/reconnect/wake).
    #       exec = [
    #         "$HOME/.nix-profile/bin/swaysome init 1"
    #         "systemctl --user start swww-restore.service"
    #       ];
    #     };
    #   }
    #
    #   # Fallback: no TV output, keep usually-OFF outputs disabled.
    #   {
    #     profile = {
    #       name = "desk";
    #       outputs = [
    #         (monitors.samsungMain // { position = "0,0"; })
    #         (monitors.nslVertical // { position = "2400,-876"; })
    #         (monitors.philipsTv // { status = "disable"; })
    #         (
    #           monitors.bnqLeft
    #           // {
    #             status = "enable";
    #             position = "-1920,0";
    #           }
    #         )
    #       ];
    #       # Restore wallpaper when kanshi applies this profile (monitor connect/reconnect/wake).
    #       exec = [
    #         "$HOME/.nix-profile/bin/swaysome init 1"
    #         "systemctl --user start swww-restore.service"
    #       ];
    #     };
    #   }
    # ];

    # Pin DESK system base to nixos-25.11 (stable). Mirrors the LAPTOP_X13
    # change from 2026-05-14 (commits 32d0712 + 3476490 + 991f714). pkgs
    # resolves to pkgs-stable; user-facing apps stay on unstable via
    # explicit pkgs-unstable.X pins (Vivaldi, OBS, IDEs, dev runtimes, etc.).
    systemStable = true;
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";

    # us(intl) compose override is OFF for consistency: Chromium/Electron use a
    # hardcoded compose table that can't be changed on Wayland, so "'s" -> ś
    # there no matter what. Rather than have terminals/Qt behave differently from
    # browsers, we keep stock dead-key behavior everywhere and type ' + space for
    # a literal apostrophe (let's = l e t ' space s). Flip to true to re-enable
    # the smart "'s" fallback in compose-aware apps only. (See xcompose.nix.)
    usIntlApostropheComposeFix = false;
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "dialout"
    ];

    theme = "ashes";
    wm = "sway";  # Switched from plasma6 for faster builds (no KDE compilation)
    wmEnableHyprland = false;

    fileManager = "dolphin";

    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";

    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    spotifyUrlHandlerEnable = true; # open.spotify.com links open the Spotify app
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "JetBrainsMono Nerd Font Mono";
    # fontPkg will be set in flake-base.nix based on font name

    # Home packages
    homePackages = pkgs: pkgs-unstable: [
      # DESK-specific packages
      pkgs.clinfo # OpenCL diagnostics
      pkgs.python3Packages.uptime-kuma-api # Python wrapper for Uptime Kuma API

      # NOTE: Development tools in user/app/development/development.nix (controlled by developmentToolsEnable flag)
      # NOTE: Gaming & emulators in user/app/games/games.nix (controlled by gaming flags)
    ];

    # ============================================================================
    # SOFTWARE & FEATURE FLAGS (USER) - Centralized Control
    # ============================================================================

    # === Package Modules (User) ===
    userBasicPkgsEnable = true; # Basic user packages (browsers, office, communication, etc.)
    userAiPkgsEnable = true; # AI & ML packages (lmstudio, ollama-rocm) - DESK only
    openCodeEnable = true;   # OpenCode coding agent on the local GPU (models below, in systemSettings)
    userMediaRecordingEnable = true; # OBS Studio, HandBrake, ffmpeg-full — DESK only
    userGamedevPkgsEnable = true; # Godot 4 — Komi Adventures game project
    meetingTranscribeEnable = true; # Local meeting recording + whisper.cpp transcription (Vulkan/AMD)
    rangerFullPreviewEnable = true; # Full ranger preview (fonts, ebooks, spreadsheets, etc.)

    # === Browsers ===
    # Zen installed ALONGSIDE Vivaldi (does not claim the http/https handlers);
    # migrating off Vivaldi. zenSineEnable bakes the Sine bootloader into the
    # wrapper so the sine-web-panels mod can restore sidebar web panels, which
    # Zen removed in 1.11b. See user/app/browser/zen.nix.
    zenBrowserEnable = true;
    zenSineEnable = true;
    # Migrated from the Flatpak install — must match the existing directory.
    zenProfileDir = "8fl3a3xu.Default (release)";
    zenIsDefaultBrowser = true; # Zen owns http/https + the Spotify router; Vivaldi stays installed

    # === Gaming & Entertainment ===
    gamesEnable = true; # Master gate for gaming submodules
    gamesLightEnable = true; # Light gaming: RetroArch, emulators, light games, pegasus
    protongamesEnable = true; # Heavy gaming: Wine, Bottles, Lutris, Proton
    starcitizenEnable = true; # Enable Star Citizen support and optimizations
    GOGlauncherEnable = true; # Enable Heroic Games Launcher for GOG games
    steamPackEnable = true; # Enable Steam gaming platform
    vkbasaltEnable = true; # vkBasalt Vulkan post-processing (CAS) — opt-in per game via ENABLE_VKBASALT=1
    dolphinEmulatorPrimehackEnable = true; # Enable Dolphin Emulator with Primehack
    rpcs3Enable = false; # Temporarily disabled — upstream nixpkgs-unstable build broken (GLEW/GLX link error); re-enable once fixed

    # === Shell Customization ===
    # starshipEnable = true is now the default in lib/defaults.nix
    starshipHostStyle = "bold cyan"; # Cyan for DESK

    zshinitContent =
      # Common keybindings for all shells
      ''
        # Keybindings for Home/End/Delete keys
        bindkey '\e[1~' beginning-of-line     # Home key
        bindkey '\e[4~' end-of-line           # End key
        bindkey '\e[3~' delete-char           # Delete key
        # Ctrl+Arrow word navigation
        bindkey ''$'\e[1;5C' forward-word   # Ctrl+Right
        bindkey ''$'\e[1;5D' backward-word  # Ctrl+Left

        # Multi-line editing with Shift+Enter
        # Create a custom widget to insert a literal newline
        insert-newline() {
          LBUFFER="$LBUFFER"$'\n'
        }
        zle -N insert-newline

        # Bind Shift+Enter to insert newline (various terminal escape sequences)
        bindkey '\e[13;2u' insert-newline    # Kitty, Alacritty (CSI u mode)
        bindkey '\e[27;2;13~' insert-newline # Some other terminals
        bindkey '\eOM' insert-newline        # Alternative sequence
      ''
      # Add custom PROMPT only if Starship is disabled
      + (if (!starshipEnable) then ''

        PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{magenta}%m%f%u:%F{yellow}%~%f
        %F{green}→%f "
        # RPROMPT removed - was causing visual issues with excess spacing
        [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
      '' else ''
        # Starship prompt is enabled - no custom PROMPT needed
        [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
      '');

    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519 # Generate this key for github if needed
        AddKeysToAgent yes

      # VPS (SSH via Tailscale or WireGuard — VPN-only, non-standard port)
      Host vps vps-prod 100.64.0.6 172.26.5.155
        Port 56777
        ForwardAgent yes
    '';
  };
}
