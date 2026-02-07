# Environment Profile Variable Module (Darwin/macOS)
# Sets ENV_PROFILE environment variable for context awareness
# Used by Claude Code to identify which machine/container it's running on
#
# This enables:
# - Context-aware prompts and shell customization
# - Remote operation awareness (Claude can SSH to other nodes when needed)
# - Profile-specific behavior in scripts
#
# Usage in profile config:
#   systemSettings.envProfile = "MACBOOK_KOMI";
#
# For NixOS, use system/shell/env-profile.nix instead.

{ systemSettings, lib, pkgs, ... }:

{
  # Set ENV_PROFILE in launchd environment (available to all processes)
  launchd.user.envVariables = {
    ENV_PROFILE = systemSettings.envProfile;
  };

  # Set in /etc/profile for shell sessions
  environment.etc."profile".text = lib.mkAfter ''
    export ENV_PROFILE="${systemSettings.envProfile}"
  '';

  # Also add to zshrc for zsh sessions (most common on macOS)
  programs.zsh.shellInit = ''
    export ENV_PROFILE="${systemSettings.envProfile}"
  '';
}
