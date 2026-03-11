# Lenovo Thinkpad hardware optimizations via nixos-hardware
# Provides Intel CPU optimizations, thermal throttling, SSD tuning, and Thinkpad-specific configs
{
  lib,
  systemSettings,
  inputs,
  ...
}:

let
  # Map thinkpadModel to nixos-hardware module path
  thinkpadModules = {
    "lenovo-thinkpad-l14-intel" = inputs.nixos-hardware.nixosModules.lenovo-thinkpad-l14-intel;
    "lenovo-thinkpad-x280" = inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x280;
    "lenovo-thinkpad-t490" = inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t490;
    "lenovo-thinkpad-x13-amd" = inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x13-amd;
  };

  # Get the module based on thinkpadModel setting
  selectedModule = thinkpadModules.${systemSettings.thinkpadModel} or null;
in
{
  imports =
    if systemSettings.thinkpadEnable && selectedModule != null then
      [ selectedModule ]
    else
      [ ];

  # Warn if thinkpadEnable is true but model is invalid
  warnings =
    lib.optional
      (systemSettings.thinkpadEnable && selectedModule == null)
      "thinkpadEnable is true but thinkpadModel '${systemSettings.thinkpadModel}' is not recognized. Available models: ${lib.concatStringsSep ", " (lib.attrNames thinkpadModules)}";

  # PS/2 keyboard and touchpad support for ThinkPads
  # i8042/atkbd in initrd: needed for built-in keyboard at LUKS password prompt
  # psmouse: PS/2 touchpad driver (not autoloaded on some kernels)
  # i8042.reset: fixes AUX port not initializing on kernel 6.19+
  boot.initrd.availableKernelModules = lib.mkIf systemSettings.thinkpadEnable [
    "i8042" "atkbd"
  ];
  boot.kernelModules = lib.mkIf systemSettings.thinkpadEnable [ "psmouse" "thinkpad_acpi" ];
  boot.kernelParams = lib.mkIf systemSettings.thinkpadEnable [ "i8042.reset=1" "i8042.nomux=1" ];

  # Enable fan control via thinkpad_acpi so the OS can set fan levels when needed
  boot.extraModprobeConfig = lib.mkIf systemSettings.thinkpadEnable ''
    options thinkpad_acpi fan_control=1
  '';

  # Thinkfan daemon — active fan curve management
  # Uses ThinkPad ACPI thermal zones and fan interface
  # Requires fan_control=1 (set above) for userspace fan control
  services.thinkfan = lib.mkIf (systemSettings.thinkpadEnable && (systemSettings.thinkfanEnable or false)) {
    enable = true;

    sensors = [
      {
        type = "tpacpi";
        query = "/proc/acpi/ibm/thermal";
      }
    ];

    fans = [
      {
        type = "tpacpi";
        query = "/proc/acpi/ibm/fan";
      }
    ];

    # Balanced fan curve: quiet at idle, progressive ramp, full speed at 86°C
    # Format: [level  lower_temp  upper_temp]
    # - Rising: next level when ANY sensor exceeds upper_temp
    # - Falling: prev level when ALL sensors drop below lower_temp
    # - 5°C hysteresis between levels prevents fan oscillation
    levels = [
      [0               0  50]     # Silent — idle, light browsing
      [1              45  55]     # Whisper — light multitasking
      [2              50  60]     # Low — video playback, moderate use
      [3              55  65]     # Medium — compilation, heavy tabs
      [4              60  70]     # Medium-high — sustained workload
      [5              65  75]     # High — gaming, heavy compile
      [6              70  80]     # Very high — intense sustained load
      [7              75  86]     # Max firmware speed
      ["level full-speed" 83 32767]  # Bypass firmware limit — kicks in at 86°C
    ];
  };
}
