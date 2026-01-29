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
}
