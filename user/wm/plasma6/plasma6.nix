{ config, pkgs, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # (home.file) > set dotfiles for plasma under .config
  home.file.".config/xmonad/xmonad.hs".source = ./xmonad.hs;
  home.file.".config/xmonad/startup.sh".source = ./startup.sh;
}
