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
  # Updated for nix-darwin compatibility
  security.pam.services.sudo_local.touchIdAuth = darwin.touchIdSudo;

  # Firewall configuration
  # Updated to use new networking.applicationFirewall options
  networking.applicationFirewall = {
    enable = true;
    allowSigned = true;
    allowSignedApp = true;
    enableStealthMode = false;
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
