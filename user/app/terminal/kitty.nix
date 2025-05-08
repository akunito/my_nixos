{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    kitty
  ];
  programs.kitty.enable = true;
  programs.kitty.settings = {
    background_opacity = lib.mkForce "0.85";
    modify_font = "cell_width 90%";
    hide_window_decorations = "yes"; # borderless
    font_size = "12";
  };
  programs.kitty.keybindings = {
    "ctrl+c" = "copy_or_interrupt";
    "ctrl+v" = "paste_from_clipboard";
  };
}
