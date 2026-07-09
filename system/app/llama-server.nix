# Local LLM inference server — llama.cpp `llama-server`, Vulkan backend.
#
# OpenAI-compatible API at http://<host>:<port>/v1 . Vulkan is the fastest and
# best-supported backend on this RDNA4 GPU (RX 9070 XT / gfx1201) — ~20-30%
# faster than ROCm and it reuses the exact `override { vulkanSupport = true; }`
# pattern already proven on this machine for whisper.cpp (RADV).
#
# Exposure: bound to `llamaServerHost` but the port is only opened on the
# tailscale0 interface (not LAN/WAN). Optional `--api-key` on top.
#
# VRAM: gpt-oss-20b (MXFP4) is ~13GB, so the loaded model competes with gaming
# on the same GPU. Hence `llamaServerAutoStart = false` by default: the unit
# exists but is NOT wantedBy multi-user.target — start it on demand (manually,
# or via the wake-and-wait proxy) so it doesn't hold VRAM while gaming.
#
# Usage in profile:
#   llamaServerEnable = true;
#   llamaServerHost = "0.0.0.0";
#   llamaServerPort = 8090;
#   llamaServerModelHfRepo = "ggml-org/gpt-oss-20b-GGUF";
#
# Bring-up:
#   systemctl start llama-server            # first start downloads the GGUF
#   journalctl -u llama-server -f           # watch model load + Vulkan device
#   curl http://127.0.0.1:8090/v1/models
#
# See: memory reference_desk_wol (wake-on-demand context)
{ config, pkgs, pkgs-unstable, lib, systemSettings, ... }:
let
  cfg = systemSettings;
  enabled = cfg.llamaServerEnable or false;
  autoStart = cfg.llamaServerAutoStart or false;
  host = cfg.llamaServerHost or "0.0.0.0";
  port = cfg.llamaServerPort or 8090;
  hfRepo = cfg.llamaServerModelHfRepo or "ggml-org/gpt-oss-20b-GGUF";
  hfFile = cfg.llamaServerModelHfFile or "";
  ctxSize = cfg.llamaServerCtxSize or 16384;
  gpuLayers = cfg.llamaServerGpuLayers or 999;
  apiKey = cfg.llamaServerApiKey or "";
  extraArgs = cfg.llamaServerExtraArgs or [ "--jinja" ];
  openFwTs = cfg.llamaServerOpenFirewallTailscale or true;

  # Vulkan-accelerated llama.cpp on unstable (newest RDNA4 + gpt-oss support).
  # DESK pins pkgs=stable, so use pkgs-unstable explicitly (repo convention).
  llamaVulkan = pkgs-unstable.llama-cpp.override { vulkanSupport = true; };

  modelRef = if hfFile != "" then "${hfRepo}:${hfFile}" else hfRepo;

  args = [
    "--host" host
    "--port" (toString port)
    "-ngl" (toString gpuLayers)   # offload all layers to the GPU
    "-c" (toString ctxSize)
    "-hf" modelRef                # auto-download GGUF from HuggingFace on first run
  ]
  ++ lib.optionals (apiKey != "") [ "--api-key" apiKey ]
  ++ extraArgs;
in
{
  config = lib.mkIf enabled {
    systemd.services.llama-server = {
      description = "llama.cpp OpenAI-compatible inference server (Vulkan)";
      wantedBy = lib.optional autoStart "multi-user.target";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        # Vulkan ICD discovery (RADV) — same path used by gaming + whisper.cpp here.
        VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
        # GGUF cache + HOME land in the StateDirectory below.
        LLAMA_CACHE = "/var/lib/llama-server";
        HOME = "/var/lib/llama-server";
      };

      serviceConfig = {
        ExecStart = "${lib.getExe' llamaVulkan "llama-server"} ${lib.escapeShellArgs args}";
        DynamicUser = true;
        StateDirectory = "llama-server";
        SupplementaryGroups = [ "video" "render" ];  # /dev/dri access for the GPU
        Restart = "on-failure";
        RestartSec = 5;
        # Moderate hardening — kept loose enough for GPU + HF download.
        # If Vulkan init fails under this, relax ProtectSystem first.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # Expose the port ONLY over Tailscale (localhost always works regardless).
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.mkIf openFwTs [ port ];
  };
}
