{ pkgs, lib, userSettings, systemSettings, ... }:

{
  # Enable keyd service for keyboard remapping
  # Keyd works at the kernel input level, so it works in Sway, Plasma, Hyprland, console, TTY, and login screens
  # Enable for all GUI environments: Sway, Plasma 6, Hyprland
  # This covers personal, desk, laptops, and work computers that use GUI
  services.keyd = lib.mkIf (
    userSettings.wm == "sway" || 
    systemSettings.enableSwayForDESK == true ||
    userSettings.wm == "plasma6" ||
    userSettings.wm == "hyprland" ||
    (systemSettings ? wmEnableHyprland && systemSettings.wmEnableHyprland == true)
  ) {
    enable = true;
    
    keyboards.default = {
      ids = [ "*" ];  # Apply to all keyboards
      settings = {
        main = {
          # Map CapsLock to Ctrl+Alt+Meta (Super) - this equals Hyper key (Mod4+Control+Mod1)
          # This disables normal Caps Lock functionality (no uppercase toggle)
          capslock = "C-A-M";
        };
      };
    };
  };
}
