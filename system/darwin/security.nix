# Security Configuration for macOS
# Configures Touch ID for sudo, Gatekeeper, and other security settings
# Settings are controlled by systemSettings.darwin.* options

{ config, pkgs, lib, systemSettings, userSettings, ... }:

let
  darwin = systemSettings.darwin;
in
{
  # Enable Touch ID for sudo authentication with pam_reattach
  # pam_reattach allows Touch ID to work in tmux, Kitty, and other terminal emulators
  # Without it, Touch ID only works in Terminal.app
  security.pam.services.sudo_local = {
    touchIdAuth = darwin.touchIdSudo;
    text = lib.mkIf darwin.touchIdSudo ''
      # Enable pam_reattach to make Touch ID work in tmux and other terminal emulators
      auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
      auth       sufficient     pam_tid.so
    '';
  };

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
