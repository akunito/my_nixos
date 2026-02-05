# Darwin (macOS) Base System Configuration
# This is the nix-darwin system configuration for macOS profiles
# Profile-specific configs (MACBOOK-KOMI, etc.) will import and extend this

{ config, pkgs, lib, systemSettings, userSettings, inputs, ... }:

{
  imports = [
    ../../system/darwin/defaults.nix
    ../../system/darwin/homebrew.nix
    ../../system/darwin/keyboard.nix
    ../../system/darwin/security.nix
  ];

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" userSettings.username ];
    };
    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 3; Minute = 0; };
      options = "--delete-older-than 30d";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # System programs
  programs.zsh.enable = true;

  # Create /etc/zshrc that loads nix-darwin environment
  programs.zsh.enableCompletion = true;
  programs.zsh.enableBashCompletion = true;

  # Set hostname
  networking.hostName = systemSettings.hostname;

  # Set primary user for system.defaults options
  # Required for nix-darwin to apply user-specific system defaults
  system.primaryUser = userSettings.username;

  # User configuration
  users.users.${userSettings.username} = {
    name = userSettings.username;
    home = "/Users/${userSettings.username}";
    shell = pkgs.zsh;
  };

  # System state version (nix-darwin)
  system.stateVersion = 5;

  # Set Git commit hash for darwin-version.
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
}
