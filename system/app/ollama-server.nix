# Local LLM inference server — Ollama, ROCm backend.
#
# Replaces system/app/llama-server.nix as the DESK inference backend. The two
# are mutually exclusive (same port) and an assertion enforces it, so a rollback
# is one flag: set ollamaServerEnable = false and llamaServerEnable = true.
#
# WHY OLLAMA, given llama.cpp+Vulkan is faster here:
#   SecondBrain (the Minecraft NPC mod) builds its OpenAI client as
#   SimpleOpenAI.builder().apiKey(...) with no .baseUrl(), so its OPENAI mode is
#   hardwired to api.openai.com and cannot be pointed at our gateway. Its only
#   configurable endpoint is `ollamaUrl`, which speaks Ollama's native /api/chat
#   via ollama4j. llama.cpp does not serve that API.
#   Ollama serves BOTH: /api/chat for SecondBrain and /v1/chat/completions for
#   LiteLLM. One server, one model in VRAM, two consumers.
#
# THE COST — PAID OFF 2026-09-01, this note is kept for the history:
#   Choosing Ollama used to mean choosing ROCm, because nixpkgs shipped only
#   libggml-hip.so and no Vulkan backend, and on RDNA4 Vulkan is the faster of
#   the two. nixpkgs-unstable now carries `ollama-vulkan` as a separate package
#   (same 0.32.14, only the ggml backend differs), so the trade no longer
#   exists — see ollamaServerBackend below. Both were benchmarked here; Vulkan
#   won on speed AND on reporting free VRAM honestly, and is now the default on
#   DESK. ROCm remains one flag away.
#
# Architecture (all on DESK):
#   ollama.service  -> always up, but nearly free when idle: with no model
#                      loaded it is a small Go process holding no VRAM.
#                      OLLAMA_KEEP_ALIVE unloads the model after idle.
#
# This is deliberately simpler than the llama.cpp module it replaces. That one
# needed socket activation because llama-server holds VRAM from the moment it
# starts; Ollama loads and unloads per model, so the process can just stay up
# and the idle behaviour is a single env var.
#
# TWO MODELS, ONE CARD (2026-09-01):
#   ollamaServerModel        the always-on workload — small, latency-critical,
#                            must survive alongside a Minecraft client. Today
#                            gpt-oss:20b (MoE, ~3.6B active, ~12 GiB, 69 tok/s).
#   ollamaServerCustomModels heavier models for agent work (Hermes), built here
#                            from a Modelfile. They are NOT expected to coexist
#                            with a game, and OLLAMA_MAX_LOADED_MODELS=1 means
#                            they never coexist with the model above either.
#
# Why Qwen3.8-27B is a CUSTOM model and not just a library tag: the smallest
# build Ollama publishes is qwen3.8:27b at 16.81 GB of weights plus a 0.93 GB
# vision projector — more than this entire 16304 MiB card. It only fits from a
# sub-Q4 GGUF. Sizes measured against the desktop's real VRAM baseline
# (~2.9 GiB for Sway + browser + editor, so ~13.4 GiB free):
#   UD-IQ3_XXS 10.93 GB   comfortable
#   UD-IQ3_S   12.04 GB   the default here — ~1.3 GiB left for KV + buffers
#   UD-Q3_K_XL 13.15 GB   too tight
#   UD-IQ4_XS  14.25 GB   needs a bare desktop
# Qwen3.8 runs linear attention on 48 of 64 layers, so its KV cache is far
# smaller than a normal 27B's — which is what makes IQ3_S viable at 16k ctx.
#
# THINKING IS ON BY DEFAULT in Qwen3.8 and must be turned off for our callers.
# Ollama's /v1/chat/completions accepts the OpenAI-standard `reasoning_effort`,
# and "none" disables thinking outright — so LiteLLM sets it per model and no
# chat-template patching is needed. Left on, this repeats the GLM-4.6V-Flash
# failure recorded in profiles/DESK-config.nix: hundreds of reasoning tokens
# spent before the first word of the answer, and an EMPTY reply whenever the
# caller's max_tokens runs out mid-thought.
#
# Bring-up / verify:
#   curl http://127.0.0.1:8090/api/tags                  # Ollama native
#   curl http://127.0.0.1:8090/v1/models                 # OpenAI-compatible
#   ollama-pull                                          # fetch/build every model
#   rocm-smi --showmeminfo vram                          # drops back when idle
#   systemctl status ollama                              # a refusal prints the free/floor figures
{ config, pkgs, pkgs-unstable, lib, systemSettings, userSettings, ... }:
let
  cfg = systemSettings;
  enabled = cfg.ollamaServerEnable or false;
  host = cfg.ollamaServerHost or "0.0.0.0";
  port = cfg.ollamaServerPort or 8090;
  model = cfg.ollamaServerModel or "gpt-oss:20b";
  keepAlive = cfg.ollamaServerKeepAlive or "15m";
  ctxSize = cfg.ollamaServerCtxSize or 8192;
  openFwTs = cfg.ollamaServerOpenFirewallTailscale or true;
  # A GAMING BACKSTOP, not a "does the model fit" check — that distinction was
  # wrong here and it cost us. The old floor was 13 GiB free, sized to gpt-oss:20b,
  # and it gates the SERVICE rather than a model. Measured on this desktop
  # 2026-09-01: Sway + Zen + VSCode + terminals alone hold ~2.9 GiB and a single
  # Minecraft client adds 3.9 GiB, so an ordinary working session leaves ~9.5 GiB
  # free. Under the old floor ollama then refused to start at all — taking the
  # SMALL villager model down with it and sending every villager line to paid
  # DeepSeek, for no reason.
  #
  # Ollama already decides per model whether the weights fit and offloads the
  # remainder rather than dying, and OLLAMA_MAX_LOADED_MODELS=1 stops two models
  # being resident at once. So this floor only has to answer the one question
  # ollama cannot: "is a game already holding the card?". 6 GiB free is below any
  # desktop-with-Minecraft figure above and well under any real game.
  vramNeededBytes = cfg.ollamaServerVramNeededBytes or 6442450944;

  # Same lock file and the same two command names as the llama.cpp module, on
  # purpose: GameMode hooks, muscle memory and the docs all refer to
  # llama-lock / llama-unlock, and swapping the backend should not break them.
  lockFile = "/run/llama-gaming/lock";

  # nixpkgs-stable pins ollama 0.21.1. Qwen3.8-27B is a hybrid Gated-DeltaNet
  # model and its runtime landed in ollama 0.32.12, so on stable it cannot load
  # at all ("unknown architecture"). Unstable carries 0.32.14. The CLI shipped
  # to the user by userAiPkgsEnable already came from unstable, so before this
  # the client was 0.32.14 talking to a 0.21.1 server — a skew worth removing on
  # its own. Flip ollamaServerUseUnstable to false to go back to stable.
  useUnstable = cfg.ollamaServerUseUnstable or true;

  # "rocm" or "vulkan". Both come from the same ollama version; they differ only
  # in which ggml backend is compiled in (ls $out/lib/ollama: `rocm_v7_2` vs
  # `vulkan`). Benchmarked on this card 2026-09-01, 250 tokens, two runs each:
  #
  #                                        ROCm        Vulkan
  #   qwen3.8-agent (dense 27B, IQ3_S)   27.4 tok/s  30.9 tok/s   +13%
  #   gpt-oss:20b   (MoE A3.6B, MXFP4)   92.4 tok/s 106.2 tok/s   +15%
  #
  # RADV compiles native GFX1201 shaders; ROCm reaches RDNA4 through a generic
  # path. The speed is the smaller half of the win though — see the VRAM note
  # under OLLAMA_GPU_OVERHEAD below for the part that actually prevents crashes.
  backend = cfg.ollamaServerBackend or "rocm";
  ollamaPkg =
    let src = if useUnstable then pkgs-unstable else pkgs;
    in if backend == "vulkan" then src.ollama-vulkan else src.ollama-rocm;

  maxLoaded = cfg.ollamaServerMaxLoadedModels or 1;
  gpuOverhead = cfg.ollamaServerGpuOverheadBytes or 0;
  extraModels = cfg.ollamaServerExtraModels or [ ];
  customModels = cfg.ollamaServerCustomModels or [ ];

  # Render one Modelfile per custom model. Keeping sampling defaults HERE rather
  # than in each caller matters because our callers cannot all set them: MCA
  # hand-builds its request body with only "model" and "messages", and Ollama's
  # /v1 endpoint accepts no top_k at all. Whatever a model needs to behave has
  # to be baked into the model itself.
  mkModelfile = m: pkgs.writeText "Modelfile-${m.name}" (''
    FROM ${m.from}
  '' + lib.concatStringsSep "" (lib.mapAttrsToList
        (k: v: "PARAMETER ${k} ${toString v}\n") (m.parameters or { }))
    + lib.optionalString ((m.system or "") != "") ''
    SYSTEM """${m.system}"""
  '');

  # Every model this host should hold on disk: the primary, any library extras,
  # and the FROM of each custom model (ollama create pulls it if missing).
  allPulls = [ model ] ++ extraModels;

  # Ollama enumerates the iGPU too — measured on this box it reports the
  # 7800X3D's gfx1036 as a second 6.5 GiB "GPU". Left alone it can schedule
  # layers onto it. Pin to the discrete card.
  visibleDevices = cfg.ollamaServerVisibleDevices or "0";

  # --- VRAM eviction ---------------------------------------------------------
  #
  # WHAT IT DOES. Reading amdgpu's debugfs `amdgpu_evict_vram` tells TTM to move
  # every evictable buffer object out of VRAM and into GTT — the window through
  # which the GPU reaches ordinary system RAM over PCIe. Nothing is freed or
  # lost; buffers migrate back automatically the moment anything touches them.
  #
  # WHY IT IS WORTH DOING. The compositor's allocation is mostly COLD. SwayFX's
  # scenefx renderer reserves four full-output-size framebuffers per output
  # (blur_saved_pixels_buffer, effects_buffer, effects_buffer_swapped and
  # optimized_blur_buffer — scenefx-0.4.1 render/fx_renderer/fx_pass.c:1003 and
  # :1161-1166) and does so UNCONDITIONALLY: the only gate is
  # `basic_renderer = (output == NULL)`, so `blur disable` in the config changes
  # nothing. On DESK's 3840x2160 + 2560x1440 pair that is ~750 MiB that is
  # allocated, never read, and sitting in the fastest memory on the machine.
  # Left alone amdgpu only evicts under pressure, at the worst possible moment
  # and picking whatever is convenient. Doing it up front lets each consumer
  # fault back exactly what it uses.
  #
  # MEASURED ON DESK 2026-09-02 (RX 9070, 16304 MiB):
  #   idle desktop                      1250 MiB used
  #   after evict                        104 MiB used   (GTT 78 -> 1166 MiB)
  #   gpt-oss:20b loaded on top of that 13053 MiB used, of which sway 722 MiB
  #   +45 s of ordinary desktop use     13053 MiB — flat, nothing thrashing
  # Loading the same model WITHOUT evicting first lands at 13560 MiB. So the
  # desktop settles at 722 MiB instead of 1250 MiB and ~500 MiB stays reclaimed
  # for the model. The flat +45 s reading is the important one: had the desktop
  # been paging over PCIe every frame, sway's figure would have kept climbing.
  #
  # ‼️ IT BLOCKS, AND ON A BUSY DESKTOP IT LIVELOCKS. Reading the knob is not a
  # poke that returns and lets TTM work in the background: the read returns only
  # once the migration is done, in an uninterruptible kernel read that `timeout`
  # cannot cut short (D state until the kernel is finished).
  #
  # How long depends entirely on whether anything is drawing. Measured on DESK
  # 2026-09-02, same machine, same script:
  #   quiescent desktop           ~1 s, 1248 -> 659 MiB, unnoticeable
  #   lightly active desktop      14 s, and once still going at 48 s
  #   actively rendering desktop  245 s with gpu_busy_percent pegged at 98%
  # In the 245 s run VRAM oscillated 461 -> 824 -> 273 -> 666 MiB while GTT
  # moved inversely: the evictor pushes buffers out, the compositor faults them
  # straight back in, and the knob keeps looping until it manages to get
  # everything out at once. That is a livelock, and it costs the whole GPU while
  # it lasts.
  #
  # ‼️ TimeoutStartSec DOES NOT BOUND THE DAMAGE. It bounds how long systemd
  # waits before moving on; the kernel keeps churning for the full duration. So
  # a timeout protects unit ordering, not the desktop.
  #
  # Everything automatic is therefore OFF by default: no periodic timer
  # (ollamaServerEvictTimerSec = 0) and no ollama.service hook
  # (ollamaServerEvictOnOllamaStart = false). `amdgpu_evict_vram` is a debugfs
  # facility meant for exercising the eviction path, not a production knob, and
  # it behaves like one. The supported use is a DELIBERATE `llama-evict` on a
  # quiet desktop, right before loading a model you want the headroom for.
  #
  # ‼️ WHY THE GUARDS ARE NOT OPTIONAL. GTT here is 10240 MiB
  # (amdgpuGttSizeMiB) and a resident model is ~12.4 GiB. Evicting while a model
  # is loaded asks TTM to push more into GTT than GTT can hold — at best a long
  # stall, at worst a failed eviction with the GPU wedged mid-migration. The
  # same applies to a game holding several GiB of textures. So this runs ONLY
  # when the card is known to be idle, and every guard failing is a silent
  # no-op rather than an error.
  # PORTABILITY. `amdgpu_evict_vram` is an amdgpu debugfs handle: there is no
  # nvidia or i915 equivalent, so this is gated on gpuType == "amd" and an
  # assertion makes a mismatched profile fail the build instead of silently
  # doing nothing. Nothing here is sized to DESK's card: the ceiling is a
  # PERCENTAGE of whatever the card reports, and the script refuses to touch a
  # card smaller than evictMinCardBytes — which is what keeps it off an
  # APU-only box like LAPTOP_X13 (gpuType = "amd", but the only DRM node is a
  # ~512 MiB iGPU carveout, and evicting that means pushing the desktop out of
  # the only memory it has).
  #
  # The one value that IS workload-shaped rather than card-shaped is the
  # threshold: it tracks how much VRAM the DESKTOP holds, which scales with
  # monitor count and resolution, not with how big the GPU is. A single 1080p
  # screen sits far below it and the whole thing stays a no-op, which is the
  # right outcome — there is nothing worth reclaiming there.
  evictEnable = (cfg.ollamaServerEvictVram or false) && (cfg.gpuType or "none") == "amd";
  evictThreshold = cfg.ollamaServerEvictThresholdBytes or 1073741824;
  evictCeilingPct = cfg.ollamaServerEvictCeilingPercent or 25;
  evictMinCard = cfg.ollamaServerEvictMinCardBytes or 2147483648;
  evictTimerSec = cfg.ollamaServerEvictTimerSec or 0;
  evictTimeout = cfg.ollamaServerEvictTimeoutSec or 60;
  evictOnStart = cfg.ollamaServerEvictOnOllamaStart or false;
  evictMaxBusy = cfg.ollamaServerEvictMaxGpuBusyPercent or 30;

  # Unprivileged users cannot read debugfs, so `llama-evict` does not evict —
  # it drops a file in a sticky directory and a path unit runs the privileged
  # part. Exactly the shape llama-lock already uses, and for the same reason.
  evictDir = "/run/llama-evict";

  evictRun = pkgs.writeShellScript "llama-evict-run" ''
    set -u
    say() { echo "llama-evict: $*"; }

    # The discrete card, chosen the same way the preflight does it: biggest
    # mem_info_vram_total. The 512 MiB iGPU must never be the one we pick.
    CARD=""; TOTAL=0
    for d in /sys/class/drm/card*/device; do
      t=$(${pkgs.coreutils}/bin/cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
      if [ "$t" -gt "$TOTAL" ]; then TOTAL=$t; CARD=$d; fi
    done
    if [ -z "$CARD" ]; then say "no amdgpu card found — nothing to do"; exit 0; fi

    # GUARD 0 — is there a real discrete card at all? An APU-only machine
    # (LAPTOP_X13: gpuType = "amd", integrated Radeon) exposes one DRM node
    # whose "VRAM" is a small carveout of system RAM. Evicting that pushes the
    # desktop out of the only memory it has, to reach... the same RAM. Refuse.
    if [ "$TOTAL" -lt ${toString evictMinCard} ]; then
      say "biggest amdgpu card is only $(( TOTAL / 1048576 )) MiB — no discrete GPU here, skipping"
      exit 0
    fi

    USED=$(${pkgs.coreutils}/bin/cat "$CARD/mem_info_vram_used" 2>/dev/null || echo 0)
    # Card-relative, so an 8 GiB, 16 GiB or 24 GiB card all behave the same
    # without per-profile tuning.
    CEILING=$(( TOTAL / 100 * ${toString evictCeilingPct} ))

    # GUARD 1 — a game holds the card. Its textures are hot; moving them to GTT
    # would trade the LLM's problem for a stuttering game.
    if [ -e ${lockFile} ]; then
      say "gaming lock taken — skipping"; exit 0
    fi

    # GUARD 2 — a model is resident. See the GTT note above: this is the one
    # that can actually hurt. "ollama is up but will not answer" counts as
    # resident, because a load in flight looks exactly like that.
    if ${pkgs.systemd}/bin/systemctl is-active --quiet ollama.service; then
      URL=http://127.0.0.1:${toString port}/api/ps
      PS=$(${pkgs.curl}/bin/curl -sf --max-time 3 "$URL" 2>/dev/null) || {
        say "ollama is up but /api/ps did not answer — skipping (a load may be in flight)"
        exit 0
      }
      case "$PS" in
        *'"models":[]'*|*'"models": []'*) : ;;
        *) say "a model is resident — skipping"; exit 0 ;;
      esac
    fi

    # GUARD 3 — something big is on the card that did not announce itself: a
    # game started without gamemode, a stray compute job. Above the ceiling we
    # do not know whose memory it is, so we leave it alone.
    if [ "$USED" -gt "$CEILING" ]; then
      say "$(( USED / 1048576 )) MiB in use, above the $(( CEILING / 1048576 )) MiB ceiling (${toString evictCeilingPct}% of $(( TOTAL / 1048576 )) MiB) — skipping (something big holds the card)"
      exit 0
    fi

    # GUARD 4 — nothing worth reclaiming. The desktop's hot set is ~700-860 MiB
    # here, so a threshold under that would make the timer fire forever and
    # re-fault cold buffers for no gain.
    if [ "$USED" -lt ${toString evictThreshold} ]; then
      exit 0
    fi

    # GUARD 5 — the card is already working. This is a WEAK heuristic and it is
    # documented as one: gpu_busy_percent is an instantaneous utilisation
    # sample, while the livelock is caused by any client faulting buffers back
    # in, however cheaply. Measured 2026-09-02: vkcube running read 13% — under
    # the limit, so this guard passed — and the eviction livelocked anyway. It
    # catches a card that is genuinely pinned (a game that never took the lock,
    # a compute job); it does NOT make llama-evict safe to fire blindly.
    BUSY=$(${pkgs.coreutils}/bin/cat "$CARD/gpu_busy_percent" 2>/dev/null || echo 0)
    if [ "$BUSY" -gt ${toString evictMaxBusy} ]; then
      say "GPU is $BUSY% busy (limit ${toString evictMaxBusy}%) — skipping, evicting into a busy card livelocks"
      exit 0
    fi

    # debugfs exposes the card twice, as dri/<n> and dri/<pci-address>. Address
    # it by PCI id so we never evict the iGPU by accident.
    PCI=$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "$CARD")")
    KNOB="/sys/kernel/debug/dri/$PCI/amdgpu_evict_vram"
    if [ ! -e "$KNOB" ]; then
      say "no $KNOB — kernel built without debugfs?"; exit 0
    fi

    # A debugfs *get* attribute: the READ performs the eviction. Writing to it
    # returns EINVAL. Same contract as amdgpu_evict_gtt in
    # system/hardware/amdgpu-suspend-workaround.nix.
    ${pkgs.coreutils}/bin/cat "$KNOB" >/dev/null 2>&1 || true

    AFTER=$(${pkgs.coreutils}/bin/cat "$CARD/mem_info_vram_used" 2>/dev/null || echo 0)
    say "$(( USED / 1048576 )) -> $(( AFTER / 1048576 )) MiB used ($(( (USED - AFTER) / 1048576 )) MiB moved to GTT)"
    exit 0
  '';

  llamaEvict = pkgs.writeShellScriptBin "llama-evict" ''
    ${pkgs.coreutils}/bin/mkdir -p ${evictDir} 2>/dev/null || true
    ${pkgs.coreutils}/bin/touch ${evictDir}/request || exit 1
    echo "requested VRAM eviction — result: journalctl -u llama-evict -n 5 --no-pager"
  '';

  llamaLock = pkgs.writeShellScriptBin "llama-lock" ''
    ${pkgs.coreutils}/bin/touch ${lockFile} \
      && echo "local LLM locked — model will not load; any running model is stopped (frees VRAM)"
  '';
  llamaUnlock = pkgs.writeShellScriptBin "llama-unlock" ''
    ${pkgs.coreutils}/bin/rm -f ${lockFile} \
      && echo "local LLM unlocked — the next request will load the model again"
  '';

  # `llama-lock` and `llama-unlock` say what they did but not what the state IS,
  # and the state is now worth asking about: the lock is normally taken and
  # released by GameMode, not by hand, so "is it locked, and why" is the first
  # question when the local model is not answering.
  llamaStatus = pkgs.writeShellScriptBin "llama-status" ''
    if [ -e ${lockFile} ]; then
      echo "lock:     TAKEN — no model will load (a game is running, or llama-lock was run by hand)"
    else
      echo "lock:     clear"
    fi
    echo -n "service:  "; ${pkgs.systemd}/bin/systemctl is-active ollama.service
    for d in /sys/class/drm/card*/device; do
      t=$(${pkgs.coreutils}/bin/cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
      [ "$t" -lt 1073741824 ] && continue   # skip the iGPU
      u=$(${pkgs.coreutils}/bin/cat "$d/mem_info_vram_used" 2>/dev/null || echo 0)
      echo "vram:     $(( u / 1048576 )) MiB used of $(( t / 1048576 )) MiB ($(( (t - u) / 1048576 )) MiB free)"
    done
    echo -n "loaded:   "
    ${pkgs.curl}/bin/curl -sf --max-time 3 http://127.0.0.1:${toString port}/api/ps 2>/dev/null       | ${pkgs.gnugrep}/bin/grep -o '"name":"[^"]*"' | ${pkgs.gnused}/bin/sed 's/"name":"//;s/"//'       | ${pkgs.coreutils}/bin/paste -sd' ' - || echo "(unreachable)"
    echo
    for d in /sys/class/drm/card*/device; do
      t=$(${pkgs.coreutils}/bin/cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
      [ "$t" -lt 1073741824 ] && continue
      g=$(${pkgs.coreutils}/bin/cat "$d/mem_info_gtt_used" 2>/dev/null || echo 0)
      echo "gtt:      $(( g / 1048576 )) MiB parked in system RAM"
    done
    echo "toggle:   llama-lock  (block + free VRAM)   |   llama-unlock  (allow again)"
    echo "reclaim:  llama-evict  (cold desktop buffers -> GTT; no-op unless the card is idle)"
  '';

  # Pulling is NOT done at activation: these are 10-14 GB each and a nixos-rebuild
  # must not block on a download, nor fail the switch when the network is down.
  # Idempotent — re-running it only fetches what is missing, so it doubles as the
  # repair step after the model store is lost (which is exactly how the store came
  # to be EMPTY between 2026-08-21 and 2026-09-01: the backend was swapped to
  # Ollama and nobody ever ran this, so `akucraft-villager` 404'd and every
  # villager line quietly fell through to DeepSeek).
  ollamaPull = pkgs.writeShellScriptBin "ollama-pull" ''
    # Deliberately NOT `set -e`: one model failing (a bad tag, a network blip)
    # must not stop the others being fetched. The `ollama list` at the end is
    # the report — check it, not the exit code of the first step.
    export OLLAMA_HOST=127.0.0.1:${toString port}
    ollama=${lib.getExe' ollamaPkg "ollama"}
    rc=0
    ${lib.concatMapStringsSep "\n" (m: ''
      echo "==> pull ${m}"
      "$ollama" pull ${m} || { echo "!! pull ${m} FAILED" >&2; rc=1; }
    '') allPulls}
    ${lib.concatMapStringsSep "\n" (m: ''
      echo "==> create ${m.name} (FROM ${m.from})"
      "$ollama" create ${m.name} -f ${mkModelfile m} || { echo "!! create ${m.name} FAILED" >&2; rc=1; }
    '') customModels}
    echo
    "$ollama" list
    exit $rc
  '';

  # The lock has to actually free VRAM, not merely refuse the next load: a
  # resident model would keep ~14 GB pinned through a whole gaming session.
  reconcile = pkgs.writeShellScript "ollama-gaming-reconcile" ''
    if [ -e ${lockFile} ]; then
      ${pkgs.systemd}/bin/systemctl stop ollama.service
    else
      ${pkgs.systemd}/bin/systemctl start ollama.service
    fi
  '';
in
{
  config = lib.mkIf enabled {
    assertions = [{
      assertion = builtins.elem backend [ "rocm" "vulkan" ];
      message = "ollamaServerBackend must be \"rocm\" or \"vulkan\", got \"${backend}\".";
    } {
      assertion = !(cfg.ollamaServerEvictVram or false) || (cfg.gpuType or "none") == "amd";
      message = ''
        ollamaServerEvictVram = true needs gpuType = "amd" (this profile has
        "${cfg.gpuType or "none"}"). It works by reading amdgpu's debugfs
        handle /sys/kernel/debug/dri/<pci>/amdgpu_evict_vram, which no other
        driver provides. Set ollamaServerEvictVram = false on this profile.
      '';
    } {
      assertion = !(cfg.llamaServerEnable or false);
      message = ''
        ollamaServerEnable and llamaServerEnable are both true. They bind the
        same port (${toString port}) and both want the whole GPU. Pick one.
      '';
    }];

    services.ollama = {
      enable = true;
      package = ollamaPkg;
      inherit host port;
      environmentVariables = {
        # Unload the model this long after the last request, so the GPU is free
        # for games and DESK can suspend. The process stays up and keeps the
        # port answering, which is what lets the VPS treat it as always-there.
        OLLAMA_KEEP_ALIVE = keepAlive;
        OLLAMA_CONTEXT_LENGTH = toString ctxSize;
        # One model resident at a time. With a ~12 GiB villager model and a
        # ~12 GiB agent model on a 16 GiB card, letting ollama keep both would
        # overcommit and push one of them onto the CPU. At 1 it evicts instead:
        # a request for the other model unloads the first, reloads, and answers.
        # Callers pay a cold start on the switch, which is the right trade for a
        # box where the two models serve completely different workloads.
        OLLAMA_MAX_LOADED_MODELS = toString maxLoaded;
      } // lib.optionalAttrs (gpuOverhead > 0) {
        # VRAM to treat as already spent. Ollama sizes a model from what ROCm
        # calls "free", and ROCm answers for the card as if nothing else were on
        # it. Measured here 2026-09-01 with a Minecraft client up: ROCm reported
        # free="15.8 GiB" while sysfs showed 10299 MiB actually free. Ollama
        # loaded a model it projected at 11928 MiB, amdgpu then refused the work
        #   amdgpu 0000:03:00.0: [drm] *ERROR* Not enough memory for command submission!
        # and took the runner AND the game's GPU context down with it.
        #
        # Two errors stack there, and this only fixes the second one:
        #   1. ROCm hides other processes' allocations. Nothing here can fix
        #      that — the gaming lock (`llama-lock`) is still the answer before
        #      starting a game.
        #   2. Ollama's own fitter under-reads its needs. Its 11928 MiB estimate
        #      against 14517 MiB of measured usage is ~1.5 GiB short, because
        #      the vision/CLIP buffers land outside the breakdown it prints.
        # This value covers (2) with margin, so a load that will not fit is
        # declined or partly offloaded instead of faulting the GPU.
        #
        # ‼️ SET THIS TO 0 ON THE VULKAN BACKEND. Vulkan reports free VRAM
        # correctly, so the reserve becomes a second deduction from an already
        # honest number and pushes weights onto the CPU. Measured 2026-09-01
        # right after the switch: gpt-oss:20b projected 12342 MiB against a
        # reported 9807 MiB free, mapped 6713 MiB to CPU RAM, and fell from
        # 106 to 40 tok/s. This option exists for ROCm, not for Vulkan.
        OLLAMA_GPU_OVERHEAD = toString gpuOverhead;
      } // (
        # Discrete card only — see visibleDevices above. The variable that does
        # this is backend-specific: setting HIP_* under Vulkan pins nothing and
        # the 7800X3D's iGPU gets enumerated as a second device.
        if backend == "vulkan"
        then { GGML_VK_VISIBLE_DEVICES = visibleDevices; }
        else { HIP_VISIBLE_DEVICES = visibleDevices;
               ROCR_VISIBLE_DEVICES = visibleDevices; }
      );
    };

    # Refuse to come up while gaming, and do it as ExecCondition so a refusal is
    # recorded as condition-failed rather than failed — a failed unit would trip
    # the restart rate-limit and stay down after the lock is cleared.
    systemd.services.ollama.serviceConfig.ExecCondition =
      pkgs.writeShellScript "ollama-preflight" ''
        if [ -e ${lockFile} ]; then
          echo "ollama: gaming lock active (${lockFile}) — refusing to start" >&2
          exit 1
        fi
        # Ask the ONE question ollama cannot answer for itself: is a game already
        # holding the card? Not "does the model fit" — see the vramNeededBytes
        # note above for why that framing took the villager model down with it.
        #
        # (The llama.cpp module this replaces compared USED against a flat 5 GiB
        # and looped over every card, including the 512 MiB iGPU. Free VRAM on
        # the biggest card, against a low floor, reads correctly whatever else is
        # running and explains itself in the log.)
        NEED=${toString vramNeededBytes}
        CARD=""; BEST=0
        for d in /sys/class/drm/card*/device; do
          t=$(${pkgs.coreutils}/bin/cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
          if [ "$t" -gt "$BEST" ]; then BEST=$t; CARD=$d; fi
        done
        if [ -z "$CARD" ]; then
          echo "ollama: no amdgpu card exposes mem_info_vram_total — starting anyway" >&2
          exit 0
        fi
        used=$(${pkgs.coreutils}/bin/cat "$CARD/mem_info_vram_used" 2>/dev/null || echo 0)
        free=$(( BEST - used ))
        if [ "$free" -lt "$NEED" ]; then
          echo "ollama: only $(( free / 1073741824 )) GiB free on $CARD, floor is $(( NEED / 1073741824 )) GiB — refusing (a game is holding the GPU)" >&2
          exit 1
        fi
        exit 0
      '';
    systemd.services.ollama.unitConfig.StartLimitIntervalSec = 0;

    # World-writable (sticky) so any local user or a GameMode hook can toggle the
    # lock without privileges; the privileged stop is done by the path unit.
    systemd.tmpfiles.rules = [ "d /run/llama-gaming 1777 root root -" ]
      ++ lib.optional evictEnable "d ${evictDir} 1777 root root -";

    systemd.paths.ollama-gaming = {
      description = "Watch the gaming lock and reconcile the local LLM";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/run/llama-gaming";
        Unit = "ollama-gaming.service";
      };
    };
    systemd.services.ollama-gaming = {
      description = "Apply/clear the local-LLM gaming lock";
      serviceConfig = { Type = "oneshot"; ExecStart = "${reconcile}"; };
    };

    # --- llama-evict wiring ---------------------------------------------------
    #
    # A SEPARATE unit, not an ExecStartPre on ollama.service, because that unit
    # runs as User=ollama under ProtectKernelTunables=yes and ProtectSystem=
    # strict: debugfs is not reachable from inside it at any privilege level.
    #
    # Wants= plus After= gives us the pre-load hook for free. A oneshot returns
    # to inactive when it finishes, so it really does re-run on every ollama
    # start rather than being skipped as already-satisfied.
    systemd.services.llama-evict = lib.mkIf evictEnable {
      description = "Move cold GPU buffers out of VRAM into GTT";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${evictRun}";
        # Bounds how long the optional After= can hold ollama.service back, and
        # NOTHING MORE. systemd cannot kill the uninterruptible debugfs read —
        # the kernel keeps migrating for the full duration whatever this says.
        # Wants= (not Requires=) means a timed-out evict never keeps ollama
        # from starting.
        TimeoutStartSec = "${toString evictTimeout}s";
      };
    };

    # OPT-IN, and off by default. ollama.service starting looks like a good
    # moment to reclaim — after a rebuild, after a boot, and right after
    # `llama-unlock` ends a gaming session. But it is not a moment we can
    # promise the desktop is quiet, and an eviction into a busy card pegs the
    # GPU for minutes (see the livelock note above). GUARD 5 makes it *usually*
    # a no-op instead, which means the hook mostly does nothing anyway. Enable
    # it only if you have decided that trade for yourself.
    #
    # Dotted paths, not a `systemd.services.ollama = { ... }` block: this file
    # already defines .serviceConfig.ExecCondition and .unitConfig on the same
    # attribute set, and two literal definitions of the same attribute is a Nix
    # syntax error rather than a module merge.
    systemd.services.ollama.wants =
      lib.optional (evictEnable && evictOnStart) "llama-evict.service";
    systemd.services.ollama.after =
      lib.optional (evictEnable && evictOnStart) "llama-evict.service";

    # The OTHER moment a model loads is a request arriving after
    # OLLAMA_KEEP_ALIVE unloaded it, which no unit transition can see. A timer
    # is the only way to cover that — but see the "IT BLOCKS" note above: each
    # run that actually does something costs tens of seconds of fence-wait, so
    # this is OPT-IN and off unless a profile sets ollamaServerEvictTimerSec.
    # If you do turn it on, keep it long (1800s+): the model unloads after 15
    # min idle, so one sweep per half hour catches the same window at a
    # fraction of the churn. All four guards still apply on every run.
    systemd.timers.llama-evict = lib.mkIf (evictEnable && evictTimerSec > 0) {
      description = "Periodically reclaim cold VRAM while the card is idle";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "${toString evictTimerSec}s";
        AccuracySec = "60s";
        Unit = "llama-evict.service";
      };
    };

    # `llama-evict` (unprivileged) touches a file here; this runs the real work.
    systemd.paths.llama-evict = lib.mkIf evictEnable {
      description = "Watch for a manual llama-evict request";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = evictDir;
        Unit = "llama-evict.service";
      };
    };

    environment.systemPackages = [ ollamaPkg llamaLock llamaUnlock llamaStatus ollamaPull ]
      ++ lib.optional evictEnable llamaEvict;

    # Tailscale only. openFirewall would punch the port on every interface, and
    # this one answers unauthenticated prompts to a 20B model.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.mkIf openFwTs [ port ];
  };
}
