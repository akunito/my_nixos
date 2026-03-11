{
  userSettings,
  systemSettings,
  lib,
  ...
}:

{
  imports = [
    ./base.nix
    ../../system/hardware-configuration.nix
    (import ../../system/security/sshd.nix {
      authorizedKeys = systemSettings.authorizedKeys;
      inherit userSettings;
      inherit systemSettings;
      inherit lib;
    })
  ];
}
