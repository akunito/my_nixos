{ systemSettings, lib, ... }:

{
  # Overriding to disable power-profiles-daemon 
  # as it cannot work together with "tlp"
  services.power-profiles-daemon.enable = false;

  # Enable tlp service
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "performance";

      CPU_ENERGY_PERF_POLICY_ON_BAT = "performance";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 100;

      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;

      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;

      PLATFORM_PROFILE_ON_AC = systemSettings.PLATFORM_PROFILE_ON_AC;
      PLATFORM_PROFILE_ON_BAT = systemSettings.PLATFORM_PROFILE_ON_BAT;

      WIFI_PWR_ON_AC = systemSettings.WIFI_PWR_ON_AC;
      WIFI_PWR_ON_BAT = systemSettings.WIFI_PWR_ON_BAT;
    };
  };
  
  powerManagement.enable = false;
  services.logind.lidSwitch = systemSettings.lidSwitch;
  services.logind.lidSwitchExternalPower = systemSettings.lidSwitchExternalPower;
  services.logind.lidSwitchDocked = systemSettings.lidSwitchDocked;
  services.logind.powerKey = systemSettings.powerKey;

  # Disable wifi powersave for Intel Network Adapter (to avoid disconnect wifi when closing the lid)
  boot.extraModprobeConfig = lib.mkIf (systemSettings.iwlwifiDisablePowerSave == true) ''
    options iwlwifi power_save=0
  '';
}
