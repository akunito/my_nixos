# Homebrew Configuration for macOS
# Manages Homebrew casks (GUI apps) and formulas (CLI tools)
# Settings are controlled by systemSettings.darwin.homebrew* options

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  darwin = systemSettings.darwin;
in
lib.mkIf darwin.homebrewEnable {
  # Enable Homebrew
  homebrew = {
    enable = true;

    # Behavior on nix-darwin activation
    onActivation = {
      autoUpdate = darwin.homebrewOnActivation.autoUpdate;
      cleanup = darwin.homebrewOnActivation.cleanup;
      upgrade = darwin.homebrewOnActivation.upgrade;
    };

    # Global settings
    global = {
      brewfile = true;
      lockfiles = false;
    };

    # Homebrew taps (repositories)
    taps = [
      "homebrew/bundle"
      "homebrew/services"
    ];

    # CLI formulas (prefer Nix when possible)
    brews = darwin.homebrewFormulas;

    # GUI applications via casks
    casks = darwin.homebrewCasks;

    # Mac App Store apps (requires mas)
    # masApps = { };
  };
}
