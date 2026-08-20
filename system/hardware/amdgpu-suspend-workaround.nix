{ pkgs, systemSettings, lib, ... }:

# AMD GPU suspend/resume workarounds. Three INDEPENDENT mitigations for three
# different subsystems — each has its own flag, enable only what a profile needs.
#
# --- amdgpuSuspendWorkaround (SMU path, AINF-282) ---
# For the SMU regression that started in kernel 6.17.x, still unfixed in 7.0.x.
#
# Symptoms: `amdgpu suspend of IP block <smu> failed -22` followed by
# `<smu> failed -62` on resume; monitors do not wake; kernel workers stuck in
# D-state; only recovery is hard power cycle.
#
# Two-pronged:
#   1. Disable AMDGPU runtime/active-state PM via kernel params, so suspend
#      does not exercise the broken SMU code path.
#   2. Stop lactd before sleep, restart on resume — LACT keeps SMU busy and
#      reliably races the suspend transition.
#
# Trade-off: idle GPU power is slightly higher because runpm is off.
#
# This flag also installs the pre-sleep memory reclaim hook — see the TTM
# eviction section below for why it lives here rather than behind its own flag.
#
# --- amdgpuDisableIps (DMCUB/display path) ---
# For the DMCUB hang on resume. Observed on DESK 2026-08-07, kernel 7.1.5,
# RX 9070 XT (Navi 48): after ~8h in S3 the GPU took a MODE1 reset on resume,
# DMCUB came back non-responsive, and the log flooded ~6/sec with
# `Error waiting for INBOX0 HW Lock Ack` + `DMCUB error - collecting
# diagnostic data`. Every plane/cursor/flip commit then ate a full timeout,
# dropping the desktop to ~1 FPS. GPU was 0% busy — a stalled display
# pipeline, not load. No userspace recovery; DMCUB sits below the compositor.
#
# Same signature as drm/amd issue #2466 (older HW/kernel, identical
# dc_dmub_srv_wait_for_inbox0_ack flood):
#   https://gitlab.freedesktop.org/drm/amd/-/issues/2466
#
# Trade-off: a few extra watts at dGPU idle. Fine on a desktop.
#
# NOTE: the SMU mitigation does NOT cover this — different subsystem. DESK had
# amdgpuSuspendWorkaround active (runpm=0/aspm=0 confirmed live) and still hit it.
#
# --- amdgpuGttSizeMiB + reclaim hook (TTM buffer eviction path) ---
# For the suspend-time OOM that disables NVMe controllers. Observed on DESK
# 2026-08-20, kernel 7.1.8, RX 9070 XT (Navi 48), recurring every 3-4 days of
# uptime.
#
# On suspend amdgpu evicts GPU buffers, allocating with GFP_NOIO. That flag
# forbids I/O, so the kernel cannot swap anything out to make room — only
# already-free and directly-reclaimable memory is usable. After days of uptime
# the session had pinned 9.4 GiB of GTT (system RAM held by the GPU) while using
# only 900 MiB of the 16 GiB VRAM, and free RAM sat at the min watermark. Even an
# order:0 allocation then failed:
#
#   kworker/u64:15: page allocation failure: order:0, mode:GFP_NOIO|...
#     __ttm_pool_alloc -> amdgpu_ttm_tt_populate -> ttm_bo_evict
#     -> amdgpu_device_evict_resources -> amdgpu_device_suspend
#   [TTM] Buffer eviction failed
#   amdgpu 0000:03:00.0: evicting device resources failed
#   amdgpu 0000:03:00.0: PM: failed to suspend async: error -12
#
# The aborted suspend left PCI power state inconsistent, and two NVMe
# controllers then failed their own reset with the same -12 and were disabled
# outright:
#
#   nvme nvme0: Disabling device after reset failure: -12
#
# Their block devices went to 0B while still mounted, so any I/O to those mounts
# blocked forever in D-state — machine frozen with fans spinning, recoverable
# only by hard power cycle.
#
# Two-pronged:
#   1. Drop caches immediately before sleep, so eviction has headroom that
#      GFP_NOIO can actually use. Reclaimable page cache is exactly the memory
#      the kernel would otherwise have needed I/O to free. Tied to
#      amdgpuSuspendWorkaround rather than its own flag: it is pure headroom
#      with no hardware assumptions, so every profile already opted into AMD
#      suspend mitigations wants it.
#   2. Cap GTT via amdgpuGttSizeMiB, bounding how much system RAM the GPU can
#      pin in the first place (kernel default is half of RAM). Separate flag —
#      it is a real cap, and the right value depends on RAM and workload.
#
# NOTE: neither mitigation above covers this — different subsystem again. DESK
# had both amdgpuSuspendWorkaround and amdgpuDisableIps active and still hit it.

let
  cfg = systemSettings.amdgpuSuspendWorkaround or false;
  isAmd = (systemSettings.gpuType or "none") == "amd";
  enabled = cfg && isAmd;
  ipsEnabled = (systemSettings.amdgpuDisableIps or false) && isAmd;

  gttSize = systemSettings.amdgpuGttSizeMiB or null;
  gttEnabled = isAmd && gttSize != null;
in
{
  boot.kernelParams =
    lib.optionals enabled [
      "amdgpu.runpm=0"
      "amdgpu.bapm=0"
      "amdgpu.aspm=0"
    ]
    # DC_DISABLE_IPS (0x800): disable Idle Power States unconditionally. The
    # INBOX0 lock is the driver<->DMCUB handshake on the IPS wake path, so a
    # DMCUB left wedged by the resume-time MODE1 reset never acks it.
    # NOT 0x1000 (DC_DISABLE_IPS_DYNAMIC) — that one keeps IPS active across
    # suspend, which is precisely the path that breaks.
    ++ lib.optionals ipsEnabled [ "amdgpu.dcdebugmask=0x800" ]
    ++ lib.optionals gttEnabled [ "amdgpu.gttsize=${toString gttSize}" ];

  environment.etc."systemd/system-sleep/lact-pause" = lib.mkIf enabled {
    source = pkgs.writeShellScript "lact-pause" ''
      case "$1/$2" in
        pre/suspend|pre/hibernate|pre/hybrid-sleep|pre/suspend-then-hibernate)
          ${pkgs.systemd}/bin/systemctl stop lactd.service || true
          ;;
        post/suspend|post/hibernate|post/hybrid-sleep|post/suspend-then-hibernate)
          ${pkgs.systemd}/bin/systemctl start lactd.service || true
          ;;
      esac
    '';
    mode = "0755";
  };

  # Free reclaimable memory right before sleep so amdgpu's GFP_NOIO buffer
  # eviction has room. Runs last (99- prefix) so it reclaims after other
  # pre-sleep hooks have already released whatever they are going to release.
  environment.etc."systemd/system-sleep/99-amdgpu-reclaim" = lib.mkIf enabled {
    source = pkgs.writeShellScript "amdgpu-reclaim" ''
      case "$1/$2" in
        pre/suspend|pre/hibernate|pre/hybrid-sleep|pre/suspend-then-hibernate)
          ${pkgs.coreutils}/bin/sync
          echo 3 > /proc/sys/vm/drop_caches || true
          ;;
      esac
    '';
    mode = "0755";
  };
}
