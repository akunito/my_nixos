{ pkgs, ... }:
let
  # Patch for Vivaldi issue on Plasma 6 -> https://github.com/NixOS/nixpkgs/pull/292148
  # Define the package with the necessary environment variable
  vivaldi = pkgs.vivaldi.overrideAttrs (oldAttrs: {
    postInstall = ''
      wrapProgram $out/bin/vivaldi --set QT_QPA_PLATFORM_PLUGIN_PATH ${pkgs.qt5.qtbase}/lib/qt-5.15/plugins/platforms/
    '';
  });
  # and install qt5.qtbase
  # remove this wrap and qt5.qtbase when the issue is fixed officially in Plasma 6
in
{

}