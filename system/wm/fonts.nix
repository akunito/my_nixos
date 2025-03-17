{ pkgs, systemSettings, ... }:

{
  # Fonts are nice to have
  fonts.packages = systemSettings.fonts;
}
