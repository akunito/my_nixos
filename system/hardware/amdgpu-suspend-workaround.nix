{ pkgs, systemSettings, lib, ... }:

# AMD GPU suspend/resume workarounds. Two INDEPENDENT mitigations for two
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

let
  cfg = systemSettings.amdgpuSuspendWorkaround or false;
  isAmd = (systemSettings.gpuType or "none") == "amd";
  enabled = cfg && isAmd;
  ipsEnabled = (systemSettings.amdgpuDisableIps or false) && isAmd;
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
    ++ lib.optionals ipsEnabled [ "amdgpu.dcdebugmask=0x800" ];

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
}
