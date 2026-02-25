{ config, pkgs, lib, userSettings, systemSettings, inputs, ... }:

{
  # Voxtype - Local voice dictation for Sway
  # Hold Super+V → speak → release → text appears at cursor
  # Uses whisper.cpp engine, runs fully local, no cloud dependency
  # Equivalent to open-wispr on macOS (MACBOOK-KOMI)

  # Install voxtype and required dependencies
  home.packages = [
    inputs.voxtype.packages.${pkgs.system}.default
    pkgs.wtype # Text injection for Wayland (recommended by voxtype)
  ];

  # Sway keybindings for hold-to-speak workflow
  # This configuration is merged into wayland.windowManager.sway.config.keybindings
  # when Sway is enabled (userSettings.wm == "sway")
  wayland.windowManager.sway.config.keybindings = lib.mkIf (userSettings.wm == "sway") {
    # Hold Super+V to record, release to transcribe and paste
    # --no-repeat: Only trigger on initial key press (not continuous repeat)
    # --release: Trigger on key release
    # Mod4 = Super key (standard Sway modifier)
    "--no-repeat Mod4+v" = "exec voxtype record start";
    "--release Mod4+v" = "exec voxtype record stop";
  };

  # Note: Voxtype configuration lives at ~/.config/voxtype/config.toml
  # On first run, voxtype will download the whisper.cpp model (base.en by default)
  # You can configure model size, language, and other settings in the config file
  # See: https://github.com/peteonrails/voxtype#configuration
}
