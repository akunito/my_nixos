{ pkgs, systemSettings, lib, ... }:

# Periodic VRAM / GTT / MemAvailable sampler for AMD GPUs.
#
# Exists because the amdgpu suspend-OOM investigation (see
# amdgpu-suspend-workaround.nix) could only be settled with a long time series:
# the failure is a slow ratchet across suspend cycles, invisible in any single
# snapshot. A 4.7-day capture showed the GTT floor climbing 944 -> 2544 -> 3131
# -> 4290 -> 5205 MiB, one step per suspend, which is what identified the cause
# and cleared the local LLM of blame.
#
# Keep it on to confirm the mitigation holds. The signature of regression is
# gtt_used ratcheting up across resumes while vram_used stays low — an inverted
# ratio (low VRAM, multi-GiB GTT) is the pre-crash state.
#
# Output goes to the journal, not a file, so it rotates and survives reboots:
#   journalctl -u gpu-mem-sampler -o cat --since "3 days ago"
#   journalctl -u gpu-mem-sampler -o cat | awk '{print $2}'   # just gtt
#
# 60s cadence: the effect moves ~1 GiB per suspend cycle, so per-minute
# resolution is ample and costs ~1440 journal lines/day.

let
  isAmd = (systemSettings.gpuType or "none") == "amd";
  enabled = (systemSettings.gpuMemSamplerEnable or false) && isAmd;
  interval = systemSettings.gpuMemSamplerIntervalSec or 60;

  sampler = pkgs.writeShellScript "gpu-mem-sample" ''
    set -u
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gawk ]}

    for dev in /sys/class/drm/card*/device; do
      [ -r "$dev/mem_info_vram_used" ] || continue
      card=$(basename "$(dirname "$dev")")
      vram=$(( $(cat "$dev/mem_info_vram_used") / 1048576 ))
      gtt=$(( $(cat "$dev/mem_info_gtt_used") / 1048576 ))
      gtt_total=$(( $(cat "$dev/mem_info_gtt_total") / 1048576 ))
      # Skip idle secondary GPUs (e.g. the iGPU) to keep the log readable.
      [ "$vram" -lt 64 ] && [ "$gtt" -lt 64 ] && continue
      avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
      swap=$(awk '/SwapTotal/{t=$2} /SwapFree/{f=$2} END{print int((t-f)/1024)}' /proc/meminfo)
      echo "$card vram=''${vram}MiB gtt=''${gtt}/''${gtt_total}MiB memavail=''${avail}MiB swapused=''${swap}MiB"
    done
  '';
in
{
  systemd.services.gpu-mem-sampler = lib.mkIf enabled {
    description = "Sample AMD GPU VRAM/GTT and memory pressure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = sampler;
      # Read-only diagnostic: no privileges beyond reading sysfs/procfs.
      DynamicUser = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = "";
    };
  };

  systemd.timers.gpu-mem-sampler = lib.mkIf enabled {
    description = "Sample AMD GPU VRAM/GTT periodically";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "${toString interval}s";
      AccuracySec = "5s";
      Unit = "gpu-mem-sampler.service";
    };
  };
}
