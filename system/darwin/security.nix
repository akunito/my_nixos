# Security Configuration for macOS
# Configures Touch ID for sudo, Gatekeeper, and other security settings
# Settings are controlled by systemSettings.darwin.* options

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  darwin = systemSettings.darwin;
in
{
  # Enable Touch ID for sudo authentication
  # This allows using fingerprint instead of password for sudo commands
  security.pam.enableSudoTouchIdAuth = darwin.touchIdSudo;

  # Firewall configuration
  system.defaults.alf = {
    # 0 = disabled, 1 = enabled, 2 = block all incoming except essential
    globalstate = 1;
    # Allow signed apps to receive incoming connections
    allowsignedenabled = 1;
    # Allow downloaded signed apps
    allowdownloadsignedenabled = 1;
    # Stealth mode (don't respond to ICMP ping)
    stealthenabled = 0;
  };

  # Gatekeeper settings
  # Note: Gatekeeper is controlled via system settings, not nix-darwin
  # Users can adjust via: System Settings > Privacy & Security > Security

  # Require password immediately after sleep or screen saver begins
  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 0;
  };
}
