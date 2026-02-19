# Fingerprint reader support (fprintd)
# Gated by systemSettings.fprintdEnable
{ systemSettings, lib, pkgs, ... }:
{
  services.fprintd.enable = systemSettings.fprintdEnable or false;
}
