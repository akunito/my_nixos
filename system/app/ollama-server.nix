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
# Bring-up / verify:
#   curl http://127.0.0.1:8090/api/tags                  # Ollama native
#   curl http://127.0.0.1:8090/v1/models                 # OpenAI-compatible
#   ollama-pull                                          # fetch the model now
#   rocm-smi --showmeminfo vram                          # drops back when idle
#   systemctl status ollama                              # a refusal prints the free/needed figures
{ config, pkgs, lib, systemSettings, userSettings, ... }:
let
  cfg = systemSettings;
  enabled = cfg.ollamaServerEnable or false;
  host = cfg.ollamaServerHost or "0.0.0.0";
  port = cfg.ollamaServerPort or 8090;
  model = cfg.ollamaServerModel or "gpt-oss:20b";
  keepAlive = cfg.ollamaServerKeepAlive or "15m";
  ctxSize = cfg.ollamaServerCtxSize or 8192;
  openFwTs = cfg.ollamaServerOpenFirewallTailscale or true;
  # How much FREE VRAM the model needs before we let ollama start. gpt-oss:20b
  # is ~12 GiB of weights plus KV cache; 13 GiB is the floor that keeps it off
  # the CPU. Lower it if you switch to a smaller model.
  vramNeededBytes = cfg.ollamaServerVramNeededBytes or 13958643712;

  # Same lock file and the same two command names as the llama.cpp module, on
  # purpose: GameMode hooks, muscle memory and the docs all refer to
  # llama-lock / llama-unlock, and swapping the backend should not break them.
  lockFile = "/run/llama-gaming/lock";

  ollamaPkg = pkgs.ollama-rocm;

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

  # Pulling is NOT done at activation: the model is ~14 GB and a nixos-rebuild
  # must not block on a download, nor fail the switch when the network is down.
  ollamaPull = pkgs.writeShellScriptBin "ollama-pull" ''
    export OLLAMA_HOST=127.0.0.1:${toString port}
    echo "pulling ${model} — this is a one-off ~14GB download"
    exec ${lib.getExe' ollamaPkg "ollama"} pull ${model}
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
        # Ask the question that actually matters: is there room for the model?
        #
        # The llama.cpp module this replaces compared USED against a flat 5 GiB
        # and looped over every card. Both are wrong here. It looped over the
        # iGPU too (card0, a 512 MiB Raphael), and on this desktop the discrete
        # card idles around 6 GiB with nothing but the compositor and a browser
        # open - so a "used > 5 GiB means gaming" rule refuses permanently and
        # calls an ordinary desktop a game.
        #
        # Free VRAM against a required floor says what we need to know, reads
        # correctly whatever else is running, and explains itself in the log.
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
          echo "ollama: only $(( free / 1073741824 )) GiB free on $CARD, need $(( NEED / 1073741824 )) GiB — refusing (gaming, or just a busy desktop)" >&2
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
