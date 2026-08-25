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
# 2026-08-20, kernel 7.1.8, RX 9070 XT (Navi 48), roughly 1 suspend in 8-10.
#
# ROOT CAUSE: suspend/resume strands GPU buffers in GTT, and the damage
# accumulates per cycle rather than per day. Suspend evicts VRAM wholesale;
# on resume buffers migrate back only when something draws them, so anything
# idle stays parked in system RAM forever. Instrumented over 4.7 days and 5
# suspends the GTT floor ratcheted 944 -> 2544 -> 3131 -> 4290 -> 5205 MiB.
# A sample taken immediately after one resume read vram=791MiB gtt=4590MiB —
# the desktop's whole working set living in system RAM with 15 GiB of VRAM idle
# beside it. That is the same inversion seen at the crash (vram=900MiB
# gtt=9455MiB).
#
# NOT caused by the local LLM, despite the plausible correlation: llama-server
# does spill model weights into GTT when VRAM is full, but frees them cleanly
# on unload (measured: gtt 3905 -> 843 MiB the instant it stopped). Over the
# 4.7-day capture it was inactive for 36531 of 37028 samples while GTT still
# climbed to 5205 MiB.
#
# The failure itself is a threshold crossing, which is why it is intermittent.
# On suspend amdgpu evicts GPU buffers allocating with GFP_NOIO. That flag
# forbids I/O, so the kernel cannot swap anything out to make room — only
# already-free and directly-reclaimable memory is usable. Suspends with
# MemAvailable above ~5 GiB have all survived; the crash hit at ~1 GiB with
# 9.4 GiB pinned in GTT. Even an order:0 allocation then failed:
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
# Three-pronged, in order of how much work each actually does:
#   1. Drain GTT via amdgpu_evict_gtt on both sides of sleep. This is the fix —
#      it addresses the stranding directly instead of making room around it.
#      See the hook below for why reading (not writing) is correct and why it
#      succeeds where the in-suspend eviction cannot. Tied to
#      amdgpuSuspendWorkaround rather than its own flag: it is a no-op on any
#      machine whose GTT is already empty, so every profile already opted into
#      AMD suspend mitigations wants it.
#   2. Drop caches immediately before sleep, so that whatever eviction remains
#      has headroom GFP_NOIO can actually use. Reclaimable page cache is exactly
#      the memory the kernel would otherwise have needed I/O to free. Kept as a
#      cheap belt-and-braces layer behind (1).
#   3. Cap GTT via amdgpuGttSizeMiB, bounding how much system RAM the GPU can
#      pin (kernel default is half of RAM). Separate flag — it is a real cap and
#      the right value depends on RAM and workload. A backstop, not a fix: it
#      converts the crash into a bounded leak but does not stop the ratchet, and
#      set too low it will squeeze a large model's GTT spill.
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

  # Drain GTT and free reclaimable memory around sleep. Runs last (99- prefix)
  # so it reclaims after other pre-sleep hooks have released what they will.
  #
  # Reading amdgpu_evict_gtt is the load-bearing step. It is a debugfs *get*
  # attribute (mode 0400 — reading triggers the eviction; writing returns
  # EACCES), and it drains the GTT manager to ordinary pageable system memory.
  # Measured on DESK 2026-08-25 with the desktop live: gtt_used 4526 -> 29 MiB,
  # VRAM untouched, no stutter, no amdgpu errors.
  #
  # Why this works where the in-suspend eviction fails: here we are outside the
  # suspend path, so the allocator runs GFP_KERNEL — I/O permitted, swap
  # available. The doomed path runs GFP_NOIO and cannot swap. Draining GTT
  # first means the in-suspend eviction has almost nothing left to move.
  #
  # Post-resume pass matters too: resume is what strands buffers in GTT in the
  # first place (VRAM is evicted wholesale on suspend, and buffers only migrate
  # back when something draws them, which never happens for idle windows and
  # background tabs). Measured on DESK across 5 suspends: the GTT floor
  # ratcheted 944 -> 2544 -> 3131 -> 4290 -> 5205 MiB, i.e. ~1 GiB of system RAM
  # pinned per cycle, never released. Clearing on resume stops the ratchet
  # instead of only papering over it before the next sleep.
  #
  # Every amdgpu node is iterated, including its aliases (numeric DRM minor and
  # PCI-address directory both appear, and minors can shift across boots).
  # Repeat reads are idempotent — the second finds nothing to evict.
  environment.etc."systemd/system-sleep/99-amdgpu-reclaim" = lib.mkIf enabled {
    source = pkgs.writeShellScript "amdgpu-reclaim" ''
      evict_gtt() {
        for f in /sys/kernel/debug/dri/*/amdgpu_evict_gtt; do
          [ -r "$f" ] && ${pkgs.coreutils}/bin/cat "$f" > /dev/null 2>&1
        done
        return 0
      }

      # Summed GTT across amdgpu nodes, in MiB.
      gtt_now() {
        total=0
        for d in /sys/class/drm/card*/device; do
          [ -r "$d/mem_info_gtt_used" ] || continue
          total=$(( total + $(${pkgs.coreutils}/bin/cat "$d/mem_info_gtt_used") / 1048576 ))
        done
        echo "$total"
      }

      mem_avail() {
        ${pkgs.gawk}/bin/awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo
      }

      # One line per sleep transition. This is the signal the per-minute sampler
      # exists to capture, compressed to ~2 lines per cycle so it stays readable
      # in the journal long after the fine-grained series has rotated away.
      # Healthy: post-resume "before" is small. Regression: it climbs each cycle.
      report() {
        before=$(gtt_now)
        avail=$(mem_avail)
        evict_gtt
        after=$(gtt_now)
        echo "amdgpu-reclaim: $1 GTT ''${before} -> ''${after} MiB (MemAvailable ''${avail} MiB)"
      }

      case "$1/$2" in
        pre/suspend|pre/hibernate|pre/hybrid-sleep|pre/suspend-then-hibernate)
          report pre-sleep
          ${pkgs.coreutils}/bin/sync
          echo 3 > /proc/sys/vm/drop_caches || true
          ;;
        post/suspend|post/hibernate|post/hybrid-sleep|post/suspend-then-hibernate)
          report post-resume
          ;;
      esac
    '';
    mode = "0755";
  };
}
