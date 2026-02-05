# Keyboard Configuration for macOS
# Configures keyboard behavior, function keys, and shortcuts
# Settings are controlled by systemSettings.darwin.keyboard* options

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  darwin = systemSettings.darwin;
in
{
  # Keyboard settings
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = false; # Set to true if you want Caps Lock → Escape

    # Use F1, F2, etc. as standard function keys
    # When true, hold Fn to access special features (brightness, volume)
    # When false (default), F-keys trigger special features, hold Fn for F1-F12
    nonUS.remapTilde = false;
  };

  # Additional keyboard settings via defaults
  system.defaults.NSGlobalDomain = {
    # Function key behavior
    "com.apple.keyboard.fnState" = darwin.keyboardFnState;

    # Keyboard navigation (full keyboard access)
    AppleKeyboardUIMode = 3;

    # Key repeat settings (also set in defaults.nix, but ensuring consistency)
    InitialKeyRepeat = darwin.keyboardInitialKeyRepeat;
    KeyRepeat = darwin.keyboardKeyRepeat;
  };
}
