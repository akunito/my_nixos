{
  userSettings,
  systemSettings,
  lib,
  ...
}:

{
  imports = [
    ./base.nix
    (import ../../system/security/sshd.nix {
      authorizedKeys = systemSettings.authorizedKeys;
      inherit userSettings;
      inherit systemSettings;
      inherit lib;
    })
  ];
}
