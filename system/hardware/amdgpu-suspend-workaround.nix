{ pkgs, systemSettings, lib, ... }:

# AMD GPU suspend/resume workaround for the SMU regression that started in
# kernel 6.17.x and is still unfixed in 7.0.x. Tracked in AINF-282.
#
# Symptoms (without these mitigations): `amdgpu suspend of IP block <smu>
# failed -22` followed by `<smu> failed -62` on resume; monitors do not wake;
# kernel workers stuck in D-state; only recovery is hard power cycle.
#
# Two-pronged mitigation:
#   1. Disable AMDGPU runtime/active-state PM via kernel params, so suspend
#      does not exercise the broken SMU code path.
#   2. Stop lactd before sleep, restart on resume — LACT keeps SMU busy and
#      reliably races the suspend transition.
#
# Trade-off: idle GPU power is slightly higher because runpm is off.

let
  cfg = systemSettings.amdgpuSuspendWorkaround or false;
  isAmd = (systemSettings.gpuType or "none") == "amd";
  enabled = cfg && isAmd;
in
{
  boot.kernelParams = lib.mkIf enabled [
    "amdgpu.runpm=0"
    "amdgpu.bapm=0"
    "amdgpu.aspm=0"
  ];

  environment.etc."systemd/system-sleep/lact-pause" = lib.mkIf enabled {
    source = pkgs.writeShellScript "lact-pause" ''
      #!${pkgs.runtimeShell}
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
