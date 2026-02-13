# Laptop power tuning — idle power reduction
# Gated by systemSettings.laptopPowerTuningEnable (master switch)
#
# Tier 1 (Safe — always on when module enabled):
#   - Audio codec power save (snd_hda_intel)
#   - NMI watchdog disable
#   - Writeback timer 15 s
#
# Tier 2 (Moderate — individual sub-flags):
#   - i915 framebuffer compression (intelGpuFbcEnable)
#   - i915 panel self-refresh   (intelGpuPsrEnable)
#   - Intel thermald             (thermaldEnable)
#
# Tier 3 (Aggressive — requires laptopPowerTuningAggressive):
#   - PCIe ASPM powersupersave
#   - powertop auto-tune

{ config, lib, pkgs, systemSettings, ... }:

{
  # ── Tier 1: Safe (always on) ──────────────────────────────────────────

  # Audio codec power save (~0.5-1 W)
  boot.extraModprobeConfig = lib.mkAfter ''
    options snd_hda_intel power_save=1 power_save_controller=Y
  '';

  # NMI watchdog disable (~0.3-0.5 W)
  boot.kernel.sysctl."kernel.nmi_watchdog" = 0;

  # Writeback timer 15 s (~0.1-0.2 W — fewer disk wakeups)
  boot.kernel.sysctl."vm.dirty_writeback_centisecs" = 1500;

  # ── Tier 2 & 3: Kernel parameters ────────────────────────────────────

  boot.kernelParams =
    # i915 framebuffer compression (~0.1-0.3 W, Intel GPU only)
    lib.optionals (systemSettings.intelGpuFbcEnable or false) [ "i915.enable_fbc=1" ]
    # i915 panel self-refresh (~0.3-0.5 W, Intel GPU only)
    ++ lib.optionals (systemSettings.intelGpuPsrEnable or false) [ "i915.enable_psr=1" ]
    # PCIe ASPM powersupersave (~0.3-1 W, may affect NVMe/WiFi stability)
    ++ lib.optionals (systemSettings.laptopPowerTuningAggressive or false) [ "pcie_aspm.policy=powersupersave" ];

  # ── Tier 2: Services ─────────────────────────────────────────────────

  # Intel thermald — proactive thermal management (~0.2-0.5 W)
  services.thermald.enable = systemSettings.thermaldEnable or false;

  # ── Tier 3: Aggressive ───────────────────────────────────────────────

  # powertop auto-tune (~0.1-0.3 W, may conflict with TLP on some settings)
  powerManagement.powertop.enable = systemSettings.laptopPowerTuningAggressive or false;
}
