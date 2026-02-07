# Environment Profile Variable Module (NixOS)
# Sets ENV_PROFILE environment variable for context awareness
# Used by Claude Code to identify which machine/container it's running on
#
# This enables:
# - Context-aware prompts and shell customization
# - Remote operation awareness (Claude can SSH to other nodes when needed)
# - Profile-specific behavior in scripts
#
# Usage in profile config:
#   systemSettings.envProfile = "DESK";  # or "LXC_HOME", "LAPTOP_L15", etc.
#
# For macOS/darwin, use system/darwin/env-profile.nix instead.

{ systemSettings, lib, pkgs, ... }:

{
  # Set ENV_PROFILE in session environment (for interactive shells)
  environment.sessionVariables = {
    ENV_PROFILE = systemSettings.envProfile;
  };

  # Also set as regular environment variable (for systemd services, etc.)
  environment.variables = {
    ENV_PROFILE = systemSettings.envProfile;
  };

  # Set in /etc/profile.d for non-interactive shells and early shell init
  # This ensures the variable is available even before home-manager loads
  environment.etc."profile.d/env-profile.sh" = {
    text = ''
      export ENV_PROFILE="${systemSettings.envProfile}"
    '';
    mode = "0644";
  };
}
