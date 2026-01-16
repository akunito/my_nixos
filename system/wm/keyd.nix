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
      ids = [ "*" ];  # Apply to all keyboards (and keyboards with mouse buttons)
      settings = {
        main = {
          # Map CapsLock to Ctrl+Alt+Meta (Super) - this equals Hyper key (Mod4+Control+Mod1)
          # This disables normal Caps Lock functionality (no uppercase toggle)
          # Using overload: Caps Lock acts as Hyper when held, Escape when tapped
          # Note: Keychron keyboards with firmware remapping already send C-A-M directly,
          # so this remapping only affects keyboards that send standard Caps Lock keycodes
          capslock = "overload(hyper, esc)";
        };
        # Use single letter M for Meta in the suffix
        "hyper:C-A-M" = {
          # This layer is active when capslock is held
          # The ":C-A-M" suffix automatically sends Control+Alt+Meta modifiers as held modifiers
          # All keys work normally, but with the Hyper modifiers active
          # Dummy entry to prevent Nix from optimizing away the empty set
          noop = "noop";
        };
      };
    };

    # Separate entry for mice - keyd's "*" wildcard only matches keyboards, not mice
    # This ensures mouse1 mapping works for actual mouse devices
    # Note: To add more mice, add their vendor:product IDs to the ids list
     keyboards.razer_mouse = {
      ids = [ "1532:00b2" ];  # Razer DeathAdder V3 - add more mouse IDs here as needed
      settings = {
        main = {
          # Map mouse side button (mouse1) to Control+Alt modifier combination
          # Using overload: mouse1 acts as combo_C_A (Control+Alt) when held, Escape when tapped
          mouse1 = "overload(combo_C_A, noop)";
        };
        # combo_C_A layer for Control+Alt (triggered by mouse1)
        "combo_C_A:C-A" = {
          # This layer is active when mouse1 is held
          # The ":C-A" suffix automatically sends Control+Alt modifiers as held modifiers
          # All keys work normally, but with the Control+Alt modifiers active
          # Dummy entry to prevent Nix from optimizing away the empty set
          noop = "noop";
        };
      };
    };
  };
}
