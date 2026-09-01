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
# THE COST, measured and accepted:
#   On RDNA4 (gfx1201) Vulkan beats ROCm by roughly 30% on decode. nixpkgs
#   ollama ships only libggml-hip.so — no Vulkan backend — so choosing Ollama
#   means choosing ROCm. Verified 2026-08-21 that ROCm does work on this card:
#     library=ROCm compute=gfx1201 "AMD Radeon RX 9070 XT" total=15.9 GiB
#   with no CPU fallback. If the speed matters more than the unification later,
#   flip the flags back.
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
  ollamaPkg = if useUnstable then pkgs-unstable.ollama-rocm else pkgs.ollama-rocm;

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

  llamaLock = pkgs.writeShellScriptBin "llama-lock" ''
    ${pkgs.coreutils}/bin/touch ${lockFile} \
      && echo "local LLM locked — model will not load; any running model is stopped (frees VRAM)"
  '';
  llamaUnlock = pkgs.writeShellScriptBin "llama-unlock" ''
    ${pkgs.coreutils}/bin/rm -f ${lockFile} \
      && echo "local LLM unlocked — the next request will load the model again"
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
        OLLAMA_GPU_OVERHEAD = toString gpuOverhead;
        # Discrete card only — see visibleDevices above.
        HIP_VISIBLE_DEVICES = visibleDevices;
        ROCR_VISIBLE_DEVICES = visibleDevices;
      };
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
    systemd.tmpfiles.rules = [ "d /run/llama-gaming 1777 root root -" ];

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

    environment.systemPackages = [ ollamaPkg llamaLock llamaUnlock ollamaPull ];

    # Tailscale only. openFirewall would punch the port on every interface, and
    # this one answers unauthenticated prompts to a 20B model.
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.mkIf openFwTs [ port ];
  };
}
