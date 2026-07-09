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
{ config, pkgs, pkgs-unstable, lib, systemSettings, ... }:
let
  cfg = systemSettings;
  enabled = cfg.llamaServerEnable or false;
  host = cfg.llamaServerHost or "0.0.0.0";
  port = cfg.llamaServerPort or 8090;                  # public socket port
  internalPort = cfg.llamaServerInternalPort or 8091;  # backend (localhost only)
  idleTimeout = cfg.llamaServerIdleTimeout or "15min";
  hfRepo = cfg.llamaServerModelHfRepo or "ggml-org/gpt-oss-20b-GGUF";
  hfFile = cfg.llamaServerModelHfFile or "";
  ctxSize = cfg.llamaServerCtxSize or 16384;
  gpuLayers = cfg.llamaServerGpuLayers or 999;
  apiKey = cfg.llamaServerApiKey or "";
  extraArgs = cfg.llamaServerExtraArgs or [ "--jinja" ];
  openFwTs = cfg.llamaServerOpenFirewallTailscale or true;

  # Vulkan-accelerated llama.cpp on unstable (newest RDNA4 + gpt-oss support).
  llamaVulkan = pkgs-unstable.llama-cpp.override { vulkanSupport = true; };

  modelRef = if hfFile != "" then "${hfRepo}:${hfFile}" else hfRepo;

  args = [
    "--host" "127.0.0.1"          # backend is localhost-only; the proxy fronts it
    "--port" (toString internalPort)
    "-ngl" (toString gpuLayers)   # offload all layers to the GPU
    "-c" (toString ctxSize)
    "-hf" modelRef                # auto-download GGUF (cached in StateDirectory)
  ]
  ++ lib.optionals (apiKey != "") [ "--api-key" apiKey ]
  ++ extraArgs;

  waitReady = pkgs.writeShellScript "llama-wait-ready" ''
    # Block until the model is loaded and the server answers /health, so the
    # proxy (ordered After=) only forwards once we can actually serve.
    for i in $(seq 1 300); do
      ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:${toString internalPort}/health" >/dev/null 2>&1 && exit 0
      sleep 1
    done
    echo "llama-server: /health not ready after 300s" >&2
    exit 1
  '';
in
{
  config = lib.mkIf enabled {
    # Heavy backend — not auto-started; pulled in on demand by the proxy.
    systemd.services.llama-server = {
      description = "llama.cpp inference backend (Vulkan) — on-demand";
      environment = {
        # Vulkan ICD discovery (RADV) — same path used by gaming + whisper.cpp here.
        VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
        LLAMA_CACHE = "/var/lib/llama-server";
        HOME = "/var/lib/llama-server";
      };
      serviceConfig = {
        ExecStart = "${lib.getExe' llamaVulkan "llama-server"} ${lib.escapeShellArgs args}";
        ExecStartPost = "${waitReady}";
        TimeoutStartSec = "360";      # covers first-run GGUF download + model load
        StopWhenUnneeded = true;      # stop (free VRAM) once the proxy no longer needs it
        DynamicUser = true;
        StateDirectory = "llama-server";
        SupplementaryGroups = [ "video" "render" ];  # /dev/dri access for the GPU
        Restart = "on-failure";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # Cheap always-on listener. First connection activates the proxy below.
    systemd.sockets.llama-proxy = {
      description = "On-demand socket for llama-server";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "${host}:${toString port}";
      };
    };

    # Proxy the socket to the backend; exit after idle so the backend can stop.
    systemd.services.llama-proxy = {
      description = "On-demand proxy to the llama-server backend";
      requires = [ "llama-server.service" ];
      after = [ "llama-server.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=${idleTimeout} 127.0.0.1:${toString internalPort}";
      };
    };

    # Expose the public port ONLY over Tailscale (localhost always works).
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.mkIf openFwTs [ port ];
  };
}
