{ systemSettings, lib, ... }:

{
  # Overriding to disable power-profiles-daemon
  # as it cannot work together with "tlp"
  services.power-profiles-daemon.enable = systemSettings.power-profiles-daemon_ENABLE;

  # Enable tlp service
  services.tlp = lib.mkIf (systemSettings.TLP_ENABLE == true) {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = systemSettings.CPU_SCALING_GOVERNOR_ON_AC;
      CPU_SCALING_GOVERNOR_ON_BAT = systemSettings.CPU_SCALING_GOVERNOR_ON_BAT;

      CPU_ENERGY_PERF_POLICY_ON_AC = systemSettings.CPU_ENERGY_PERF_POLICY_ON_AC;
      CPU_ENERGY_PERF_POLICY_ON_BAT = systemSettings.CPU_ENERGY_PERF_POLICY_ON_BAT;

      CPU_DRIVER_OPMODE_ON_AC = "active";
      CPU_DRIVER_OPMODE_ON_BAT = "active";

      CPU_MIN_PERF_ON_AC = 10;
      CPU_MAX_PERF_ON_AC = 90;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 50;

      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;
      CPU_HWP_DYN_BOOST_ON_AC = 1;
      CPU_HWP_DYN_BOOST_ON_BAT = 0;

      START_CHARGE_THRESH_BAT0 = systemSettings.START_CHARGE_THRESH_BAT0;
      STOP_CHARGE_THRESH_BAT0 = systemSettings.STOP_CHARGE_THRESH_BAT0;

      MEM_SLEEP_ON_AC = "deep";
      MEM_SLEEP_ON_BAT = "deep";

      PLATFORM_PROFILE_ON_AC = systemSettings.PROFILE_ON_AC;
      PLATFORM_PROFILE_ON_BAT = systemSettings.PROFILE_ON_BAT;

      WIFI_PWR_ON_AC = systemSettings.WIFI_PWR_ON_AC;
      WIFI_PWR_ON_BAT = systemSettings.WIFI_PWR_ON_BAT;

      RUNTIME_PM_ON_AC = "auto";
      RUNTIME_PM_ON_BAT = "auto";

      RADEON_DPM_STATE_ON_AC = "performance";
      RADEON_DPM_STATE_ON_BAT = "battery";
      RADEON_POWER_PROFILE_ON_AC = "high";
      RADEON_POWER_PROFILE_ON_BAT = "low";

      INTEL_GPU_MIN_FREQ_ON_AC = systemSettings.INTEL_GPU_MIN_FREQ_ON_AC;
      INTEL_GPU_MIN_FREQ_ON_BAT = systemSettings.INTEL_GPU_MIN_FREQ_ON_BAT;
    };
  };

  powerManagement.enable = systemSettings.powerManagement_ENABLE;

  # LOGIND
  services.logind = lib.mkIf (systemSettings.LOGIND_ENABLE == true) {
    lidSwitch = systemSettings.lidSwitch;
    lidSwitchExternalPower = systemSettings.lidSwitchExternalPower;
    lidSwitchDocked = systemSettings.lidSwitchDocked;
    powerKey = systemSettings.powerKey;
  };

  # Disable wifi powersave for Intel Network Adapter (to avoid disconnect wifi when closing the lid)
  boot.extraModprobeConfig = lib.mkIf (systemSettings.iwlwifiDisablePowerSave == true) ''
    options iwlwifi power_save=0
  '';
}
