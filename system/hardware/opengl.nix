{ pkgs, ... }:

{
  # OpenGL (renamed to graphics)
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr.icd
  ];
}
