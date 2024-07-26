{ config, pkgs, lib, ... }:

let
  # Function to recursively get all files in a directory
  sourceDirectory = dir: {
    inherit dir;
    files = builtins.attrValues (builtins.readDir dir);
  };

  # Function to generate home.file attributes for all files in the directory
  generateHomeFiles = dir: targetDir: {
    inherit dir;
    inherit (sourceDirectory dir) files;
    inherit (lib);
    inherit (pkgs);
  }:

  let
    makeHomeFile = file: {
      source = "${dir}/${file}";
      target = "${targetDir}/${file}";
    };

    homeFiles = builtins.listToAttrs (map (file: {
      name = "home.file.\"${makeHomeFile file.target}\"";
      value = makeHomeFile file;
    }) files);
  in
    homeFiles;
in
{
  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # Directories that contain dotfiles to be sourced under their paths
  home.file = lib.mkMerge [
    (generateHomeFiles ./autostart "$HOME/.config/autostart")
    (generateHomeFiles ./desktoptheme "$HOME/.local/share/plasma/desktoptheme")
    (generateHomeFiles ./env "$HOME/.config/plasma-workspace/env")
    {
      # Set single dotfiles for plasma under .config
      "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc".source = ./plasma-org.kde.plasma.desktop-appletsrc;
      "$HOME/.config/kdeglobals".source = ./kdeglobals;
      "$HOME/.config/kwinrc".source = ./kwinrc;
      "$HOME/.config/krunnerrc".source = ./krunnerrc;
      "$HOME/.config/khotkeysrc".source = ./khotkeysrc;
      "$HOME/.config/kscreenlockerrc".source = ./kscreenlockerrc;
      "$HOME/.config/kwalletrc".source = ./kwalletrc;
      "$HOME/.config/kcminputrc".source = ./kcminputrc;
      "$HOME/.config/ksmserverrc".source = ./ksmserverrc;
      "$HOME/.config/dolphinrc".source = ./dolphinrc;
      "$HOME/.config/konsolerc".source = ./konsolerc;
      "$HOME/.config/kglobalshortcutsrc".source = ./kglobalshortcutsrc;
      "$HOME/.local/share/plasma/look-and-feel".source = ./look-and-feel;
      "$HOME/.local/share/aurorae/themes".source = ./themes;
      "$HOME/.local/share/color-schemes".source = ./color-schemes;
    }
  ];
}
