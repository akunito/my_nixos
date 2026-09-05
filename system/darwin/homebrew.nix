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
      # Homebrew removed brew bundle's --force-cleanup flag. nix-darwin still emits
      # it for cleanup modes, so pass the current flags directly instead.
      cleanup = "none";
      upgrade = darwin.homebrewOnActivation.upgrade;
      # --force is required as well: without it `brew bundle install --cleanup`
      # only prints what it would remove and exits 1, which aborts activation
      # before home-manager runs.
      extraFlags =
        if darwin.homebrewOnActivation.cleanup == "zap" then [ "--cleanup" "--zap" "--force" ]
        else if darwin.homebrewOnActivation.cleanup == "uninstall" then [ "--cleanup" "--force" ]
        else [ ];
    };

    # Global settings
    global = {
      brewfile = true;
      lockfiles = false;
    };

    # Homebrew taps (repositories)
    # Note: homebrew/bundle and homebrew/services are deprecated and migrated to core
    taps = darwin.homebrewTaps;

    # CLI formulas (prefer Nix when possible)
    brews = darwin.homebrewFormulas;

    # GUI applications via casks
    casks = darwin.homebrewCasks;

    # Mac App Store apps (requires mas)
    # masApps = { };
  };
}
