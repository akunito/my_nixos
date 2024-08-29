{ systemSettings, lib, ... }:

{
  # Overriding to disable power-profiles-daemon 
  # as it cannot work together with "tlp"
  # services.power-profiles-daemon.enable = false;

  # Enable tlp service
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "balanced";

      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "balanced";

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

      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;

      MEM_SLEEP_ON_AC = "deep";
      MEM_SLEEP_ON_BAT = "deep";

      PLATFORM_PROFILE_ON_AC = systemSettings.PLATFORM_PROFILE_ON_AC;
      PLATFORM_PROFILE_ON_BAT = systemSettings.PLATFORM_PROFILE_ON_BAT;

      WIFI_PWR_ON_AC = systemSettings.WIFI_PWR_ON_AC;
      WIFI_PWR_ON_BAT = systemSettings.WIFI_PWR_ON_BAT;

      RUNTIME_PM_ON_AC = "auto";
      RUNTIME_PM_ON_BAT = "auto";

      RADEON_DPM_STATE_ON_AC = "performance";
      RADEON_DPM_STATE_ON_BAT = "battery";
      RADEON_POWER_PROFILE_ON_AC = "high";
      RADEON_POWER_PROFILE_ON_BAT = "low";

      INTEL_GPU_MIN_FREQ_ON_AC = 250;
      INTEL_GPU_MIN_FREQ_ON_BAT = 250;
    };
  };
  
  # powerManagement.enable = false;
  # services.logind.lidSwitch = systemSettings.lidSwitch;
  # services.logind.lidSwitchExternalPower = systemSettings.lidSwitchExternalPower;
  # services.logind.lidSwitchDocked = systemSettings.lidSwitchDocked;
  # services.logind.powerKey = systemSettings.powerKey;

  # Disable wifi powersave for Intel Network Adapter (to avoid disconnect wifi when closing the lid)
  boot.extraModprobeConfig = lib.mkIf (systemSettings.iwlwifiDisablePowerSave == true) ''
    options iwlwifi power_save=0
  '';
}
