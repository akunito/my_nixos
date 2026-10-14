# Local LLM inference server — llama.cpp `llama-server`, Vulkan backend,
# socket-activated (on-demand) so it only holds VRAM while actually serving.
#
# Vulkan is the fastest, best-supported backend on this RDNA4 GPU (RX 9070 XT /
# gfx1201) and reuses the `override { vulkanSupport = true; }` pattern already
# proven here for whisper.cpp (RADV).
#
# Architecture (all on DESK):
#   llama-proxy.socket   -> cheap listener on <host>:<port> (0 VRAM), always up
#   llama-proxy.service  -> systemd-socket-proxyd -> 127.0.0.1:<internalPort>,
#                           pulls in the backend, exits after --exit-idle-time
#   llama-server.service -> the heavy backend; ExecStartPost blocks until the
#                           model is loaded (/health 200); StopWhenUnneeded so
#                           it stops (freeing VRAM) once the proxy goes idle.
# First connection: socket -> proxy -> backend loads (~cold start) -> forwards.
# Idle: proxy exits -> backend stops -> VRAM freed -> DESK can suspend.
#
# Exposure: port opened only on tailscale0 (not LAN/WAN). Optional --api-key.
#
# Bring-up / verify:
#   curl http://127.0.0.1:8090/v1/models    # first hit triggers the cold start
#   rocm-smi --showmeminfo vram             # ~14GB while serving, drops when idle
#   journalctl -u llama-server -f
#
# See: memory reference_desk_wol (wake-on-demand context)
{ config, pkgs, pkgs-unstable, lib, systemSettings, userSettings, ... }:
let
  cfg = systemSettings;
  secretsFile = "${userSettings.dotfilesDir}/secrets/domains.nix";
  enabled = cfg.llamaServerEnable or false;
  host = cfg.llamaServerHost or "0.0.0.0";
  port = cfg.llamaServerPort or 8090;                  # public socket port
  internalPort = cfg.llamaServerInternalPort or 8091;  # backend (localhost only)
  idleTimeout = cfg.llamaServerIdleTimeout or "15min";
  hfRepo = cfg.llamaServerModelHfRepo or "ggml-org/gpt-oss-20b-GGUF";
  hfFile = cfg.llamaServerModelHfFile or "";
  # Absolute path to a GGUF already on disk; when set it replaces -hf. Must live
  # under StateDirectory (/var/lib/llama-server): ProtectHome + ProtectSystem=strict
  # hide everything else from the DynamicUser.
  modelFile = cfg.llamaServerModelFile or "";
  # Vulkan ICD by GPU vendor. NVIDIA's ICD works headless with nvidia_drm blocked
  # (NAS_PROD, vulkaninfo 2026-10-13: "NVIDIA GeForce RTX 3090, driverName NVIDIA");
  # pinning one ICD also hides the 5600G's RADV iGPU from llama.cpp's device list.
  vkIcd = if (cfg.gpuType or "amd") == "nvidia"
    then "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
    else "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
  ctxSize = cfg.llamaServerCtxSize or 16384;
  parallelSlots = cfg.llamaServerParallelSlots or null;
  gpuLayers = cfg.llamaServerGpuLayers or 999;
  apiKey = cfg.llamaServerApiKey or "";
  # Preferred over llamaServerApiKey: the NAME of an attribute in
  # secrets/domains.nix. Resolved at activation into a 0400 root-owned file and
  # handed to the unit via LoadCredential, so the key never enters the
  # world-readable store (same pattern as llama-wake-proxy's apiKeyFile).
  apiKeySecret = cfg.llamaServerApiKeySecret or "";
  apiKeyFile = "/var/lib/llama-server-secrets/api-key";
  extraArgs = cfg.llamaServerExtraArgs or [ "--jinja" ];
  # KV cache type for -ctk/-ctv ("" = f16). q8_0/q4_0 need flash attention
  # (-fa on in extraArgs). An option, not extraArgs, so a preset can override it.
  kvType = cfg.llamaServerKvType or "";
  modelAlias = cfg.llamaServerModelAlias or "";
  # Template override. In the container the store path is bind-mounted read-only
  # at a fixed name; the nix backend reads the store path directly.
  chatTemplateFile = cfg.llamaServerChatTemplateFile or null;
  chatTemplateInContainer = "/etc/llama-chat-template.jinja";
  openFwTs = cfg.llamaServerOpenFirewallTailscale or true;
  vramBusy = cfg.llamaServerVramBusyBytes or 5368709120;

  # Gaming lock: a user-writable flag file (no sudo needed to toggle). While it
  # exists the backend refuses to start, and a .path unit stops any running one.
  lockFile = "/run/llama-gaming/lock";

  # Vulkan-accelerated llama.cpp on unstable (newest RDNA4 + gpt-oss support).
  llamaVulkan = pkgs-unstable.llama-cpp.override { vulkanSupport = true; };

  modelRef = if hfFile != "" then "${hfRepo}:${hfFile}" else hfRepo;

  # "vulkan": the nix llama-cpp (RDNA4 on DESK). "docker-cuda": llama.cpp's own
  # CUDA image through CDI, for NVIDIA hosts. MEASURED on NAS_PROD's RTX 3090
  # 2026-10-13, Qwen3.8-27B UD-Q4_K_XL, 3140-token prompt: Vulkan on the NVIDIA
  # ICD prefill 48 tok/s / gen 36 tok/s; CUDA prefill 1326 tok/s / gen 40 tok/s.
  # Vulkan on NVIDIA is unusable for anything with a real context. No nix CUDA
  # build: cudaSupport is never in cache.nixos.org and would recompile on every
  # bump; the image is pinned by digest instead.
  backend = cfg.llamaServerBackend or "vulkan";
  dockerImage = cfg.llamaServerDockerImage or "ghcr.io/ggml-org/llama.cpp@sha256:c4348afb91499b10fad12f92626c7a8ca8b69d6475d10c793b810cb61237ce00";
  isDocker = backend == "docker-cuda";
  dockerBin = "${config.virtualisation.docker.package}/bin/docker";
  stateDir = "/var/lib/llama-server";

  # The model-shaped arguments are built at START time, not eval time, so the
  # NAS preset manager (system/app/ai-presets.nix, `ai preset set`) can switch
  # model/ctx/slots/KV/alias/template/sampling with a restart and no rebuild.
  # ${stateDir}/preset.env (written by `ai`) overrides these Nix defaults; with
  # the file absent the server starts exactly as configured in Nix.
  presetEnvFile = "${stateDir}/preset.env";
  presetDefaults = {
    LLAMA_MODEL_FILE = modelFile;
    LLAMA_HF = modelRef;
    LLAMA_CTX = toString ctxSize;
    LLAMA_SLOTS = if parallelSlots != null then toString parallelSlots else "";
    LLAMA_KV = kvType;
    LLAMA_ALIAS = modelAlias;
    LLAMA_TEMPLATE = if chatTemplateFile != null then "${chatTemplateFile}" else "";
    # extraArgs elements carry no spaces (flags and values), so a word list is exact.
    LLAMA_EXTRA = lib.concatStringsSep " " extraArgs;
  };
  # Bash that leaves the backend's argv in "''${ARGS[@]}" (and, for docker, the
  # template mount in "''${MOUNT[@]}").
  buildArgs = ''
    # `=` not `:=`: a preset may set a value EMPTY on purpose (no chat template).
    ${lib.concatStrings (lib.mapAttrsToList (k: v: ": \"\${${k}=${v}}\"\n") presetDefaults)}
    ARGS=(--host ${if isDocker then "0.0.0.0" else "127.0.0.1"} --port ${toString internalPort} -ngl ${toString gpuLayers} -c "$LLAMA_CTX")
    if [ -n "$LLAMA_MODEL_FILE" ]; then ARGS+=(-m "$LLAMA_MODEL_FILE"); else ARGS+=(-hf "$LLAMA_HF"); fi
    ${lib.optionalString (apiKeySecret != "") ''ARGS+=(--api-key-file "$CREDENTIALS_DIRECTORY/api-key")''}
    ${lib.optionalString (apiKeySecret == "" && apiKey != "") ''ARGS+=(--api-key ${lib.escapeShellArg apiKey})''}
    [ -n "$LLAMA_ALIAS" ] && ARGS+=(-a "$LLAMA_ALIAS")
    [ -n "$LLAMA_SLOTS" ] && ARGS+=(-np "$LLAMA_SLOTS")
    [ -n "$LLAMA_KV" ] && ARGS+=(-ctk "$LLAMA_KV" -ctv "$LLAMA_KV")
    MOUNT=()
    if [ -n "$LLAMA_TEMPLATE" ]; then
      ${if isDocker then ''
      MOUNT=(-v "$LLAMA_TEMPLATE:${chatTemplateInContainer}:ro")
      ARGS+=(--chat-template-file ${chatTemplateInContainer})'' else ''
      ARGS+=(--chat-template-file "$LLAMA_TEMPLATE")''}
    fi
    # shellcheck disable=SC2206 # word list by design (see presetDefaults)
    ARGS+=($LLAMA_EXTRA)
  '';

  # Preflight gate: refuse to load while gaming (lock present, or GPU already busy).
  preflight = pkgs.writeShellScript "llama-preflight" ''
    if [ -e ${lockFile} ]; then
      echo "llama-server: gaming lock active (${lockFile}) — refusing to start" >&2
      exit 1
    fi
    # VRAM safety net for games that don't toggle the lock.
    MAXUSED=${toString vramBusy}
    for f in /sys/class/drm/card*/device/mem_info_vram_used; do
      [ -r "$f" ] || continue
      u=$(${pkgs.coreutils}/bin/cat "$f" 2>/dev/null || echo 0)
      if [ "$u" -gt "$MAXUSED" ]; then
        echo "llama-server: GPU busy ($u bytes > $MAXUSED) — likely gaming, refusing to start" >&2
        exit 1
      fi
    done
    exit 0
  '';

  llamaLock = pkgs.writeShellScriptBin "llama-lock" ''
    ${pkgs.coreutils}/bin/touch ${lockFile} \
      && echo "local LLM locked — model will not load; any running model is stopped (frees VRAM)"
  '';
  llamaUnlock = pkgs.writeShellScriptBin "llama-unlock" ''
    ${pkgs.coreutils}/bin/rm -f ${lockFile} \
      && echo "local LLM unlocked — the next request will load the model again"
  '';

  waitReady = pkgs.writeShellScript "llama-wait-ready" ''
    # Block until the model is loaded and the server answers /health, so the
    # proxy (ordered After=) only forwards once we can actually serve.
    for i in $(seq 1 300); do
      ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:${toString internalPort}/health" >/dev/null 2>&1 && exit 0
      # A backend that died (missing model, bad VRAM fit) used to keep this
      # loop polling the full 300 s, holding `systemctl start` with it.
      kill -0 "$MAINPID" 2>/dev/null || { echo "llama-server: backend exited before /health was ready" >&2; exit 1; }
      sleep 1
    done
    echo "llama-server: /health not ready after 300s" >&2
    exit 1
  '';

  # docker-cuda: the container is the sandbox (root daemon, CDI GPU). The state
  # dir is mounted at its host path so llamaServerModelFile and LLAMA_CACHE are
  # the same strings for both backends. --rm + a fixed name: a stale container
  # from a crash is removed in ExecStartPre, never left to block the next start.
  dockerStart = pkgs.writeShellScript "llama-docker-start" ''
    ${buildArgs}
    exec ${dockerBin} run --rm --name llama-server \
      --device nvidia.com/gpu=all \
      -v ${stateDir}:${stateDir} \
      "''${MOUNT[@]}" \
      -e LLAMA_CACHE=${stateDir} -e HOME=${stateDir} \
      -p 127.0.0.1:${toString internalPort}:${toString internalPort} \
      ${dockerImage} "''${ARGS[@]}"
  '';
  vulkanStart = pkgs.writeShellScript "llama-vulkan-start" ''
    ${buildArgs}
    exec ${lib.getExe' llamaVulkan "llama-server"} "''${ARGS[@]}"
  '';
in
{
  config = lib.mkIf enabled {
    assertions = [
      { assertion = backend == "vulkan" || backend == "docker-cuda";
        message = "llamaServerBackend must be \"vulkan\" or \"docker-cuda\" (got \"${backend}\")"; }
      { assertion = !isDocker || (cfg.nvidiaContainerToolkitEnable or false);
        message = "llamaServerBackend = docker-cuda needs nvidiaContainerToolkitEnable (CDI --device nvidia.com/gpu=all)"; }
      { assertion = !isDocker || apiKeySecret == "";
        message = "llamaServerApiKeySecret is not wired into the docker-cuda backend (the credential dir is outside the container)"; }
    ];

    # Heavy backend — not auto-started; pulled in on demand by the proxy.
    systemd.services.llama-server = {
      description = "llama.cpp inference backend (${backend}) — on-demand";
      requires = lib.optionals isDocker [ "docker.service" ];
      after = lib.optionals isDocker [ "docker.service" ];
      # Stop before S3: a loaded model would ride into suspend holding VRAM (on
      # NVIDIA, PreserveVideoMemoryAllocations then dumps it to /var/tmp). The
      # proxy Requires= us, so it stops too and the socket re-arms on resume.
      before = [ "sleep.target" ];
      unitConfig.Conflicts = [ "sleep.target" ];
      environment = {
        VK_ICD_FILENAMES = vkIcd;
        LLAMA_CACHE = "/var/lib/llama-server";
        HOME = "/var/lib/llama-server";
      };
      # ExecCondition (not ExecStartPre): a non-zero exit cleanly SKIPS the start
      # (marked condition-failed, not failed) so refusing during gaming doesn't
      # trip the restart rate-limit. StartLimitIntervalSec=0 belt-and-suspenders.
      #
      # StopWhenUnneeded is a [Unit] key — putting it in serviceConfig makes
      # systemd log "Unknown key ... in section [Service], ignoring" and the
      # backend then NEVER stops on its own, pinning ~14GB VRAM indefinitely.
      unitConfig = {
        StartLimitIntervalSec = 0;
        StopWhenUnneeded = true;      # stop (free VRAM) once the proxy no longer needs it
      };
      serviceConfig = {
        ExecCondition = "${preflight}";
        ExecStartPost = "${waitReady}";
        TimeoutStartSec = "360";      # covers first-run GGUF download / image pull + model load
        # The preset manager's choice (ai-presets.nix); absent = the Nix defaults above.
        EnvironmentFile = "-${presetEnvFile}";
        StateDirectory = "llama-server";
        Restart = "on-failure";
        RestartSec = 5;
      } // (if isDocker then {
        ExecStartPre = "-${dockerBin} rm -f llama-server";
        ExecStart = "${dockerStart}";
        ExecStop = "${dockerBin} stop -t 30 llama-server";
        TimeoutStopSec = "45";
      } else {
        ExecStart = "${vulkanStart}";
        DynamicUser = true;
        # These are NOT optional. They used to sit inside the api-key branch
        # below, which meant a server configured WITHOUT an api key got no
        # StateDirectory (so /var/lib/llama-server did not exist for the
        # DynamicUser and every start died on "Permission denied" fetching the
        # model) and no video/render groups (so it would have had no /dev/dri
        # even if it had started). Observed on DESK 2026-08-17.
        SupplementaryGroups = [ "video" "render" ];  # /dev/dri access for the GPU
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      }) // lib.optionalAttrs (apiKeySecret != "") {
        # Exposed to the (DynamicUser) service as %d/api-key, mode 0400.
        LoadCredential = "api-key:${apiKeyFile}";
      };
    };

    # Cheap always-on listener. First connection activates the proxy below.
    systemd.sockets.llama-proxy = {
      description = "On-demand socket for llama-server";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "${host}:${toString port}";
        # Don't let bursts of connections (e.g. repeated refused requests while
        # locked) trip the trigger rate-limit and kill the listener.
        TriggerLimitIntervalSec = "0";
      };
    };

    # Proxy the socket to the backend; exit after idle so the backend can stop.
    systemd.services.llama-proxy = {
      description = "On-demand proxy to the llama-server backend";
      requires = [ "llama-server.service" ];
      after = [ "llama-server.service" ];
      # The proxy must ALWAYS run so it consumes the accepted connection (else
      # the socket re-triggers in a loop). The gaming gate lives on the backend
      # (ExecCondition); while locked the backend is skipped, so the proxy just
      # closes the caller's connection. StartLimitIntervalSec=0 avoids lockout.
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=${idleTimeout} 127.0.0.1:${toString internalPort}";
      };
    };

    # Expose the public port ONLY over Tailscale (localhost always works).
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.mkIf openFwTs [ port ];

    # Materialise the API key at runtime (never through a derivation).
    system.activationScripts.llamaServerApiKey = lib.mkIf (apiKeySecret != "") {
      text = ''
        install -d -m 0700 -o root -g root "$(dirname ${apiKeyFile})"
        key=""
        if [ -r ${secretsFile} ]; then
          key="$(${pkgs.nix}/bin/nix eval --impure --raw \
            --expr '(import ${secretsFile}).${apiKeySecret} or ""' 2>/dev/null || true)"
        fi
        if [ -n "$key" ]; then
          umask 077
          printf '%s' "$key" > ${apiKeyFile}.tmp
          chmod 0400 ${apiKeyFile}.tmp
          mv -f ${apiKeyFile}.tmp ${apiKeyFile}
        else
          # Fail closed: without the file LoadCredential refuses to start the
          # backend, which is preferable to silently serving unauthenticated.
          echo "llama-server: llamaServerApiKeySecret is set but could not be resolved — backend will refuse to start" >&2
          rm -f ${apiKeyFile}
        fi
        unset key
      '';
    };

    # --- Gaming lockout ---------------------------------------------------
    # World-writable (sticky) dir so any local user / GameMode hook can toggle
    # the lock without privileges. The privileged "stop the model" action is
    # done by the .path unit below reacting to the file.
    systemd.tmpfiles.rules = [ "d /run/llama-gaming 1777 root root -" ];

    # Reconcile on ANY change to the lock dir (file created OR removed — both
    # bump the directory mtime, so one PathModified watch covers lock+unlock).
    systemd.paths.llama-gaming = {
      description = "Watch the gaming lock and reconcile the LLM socket";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "/run/llama-gaming";
        Unit = "llama-gaming.service";
      };
    };
    systemd.services.llama-gaming = {
      description = "Apply/clear the local-LLM gaming lock";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "llama-gaming-reconcile" ''
          if [ -e ${lockFile} ]; then
            # Locked: stop accepting connections and free VRAM immediately.
            # Callers get "connection refused" — no lingering proxy left behind.
            ${pkgs.systemd}/bin/systemctl stop llama-proxy.socket llama-proxy.service llama-server.service
          else
            # Unlocked: clear any stale state and re-arm the socket.
            ${pkgs.systemd}/bin/systemctl reset-failed llama-proxy.socket llama-proxy.service llama-server.service 2>/dev/null || true
            ${pkgs.systemd}/bin/systemctl start llama-proxy.socket
          fi
        '';
      };
    };

    # Manual toggle: `llama-lock` (before gaming) / `llama-unlock`.
    environment.systemPackages = [ llamaLock llamaUnlock ];
  };
}
