{ lib, systemSettings, pkgs, authorizedKeys ? [], ... }:

{
  security.polkit = {
    enable = true;
    extraConfig = systemSettings.polkitRules;
  };
}
