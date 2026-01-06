# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ lib, pkgs, systemSettings, userSettings, inputs, ... }:

with lib;
let
  nixos-wsl = import ./nixos-wsl;
in
{
  imports =
    [ nixos-wsl.nixosModules.wsl
      ../../system/hardware/kernel.nix # Kernel config
      ../../system/hardware/systemd.nix # systemd config
      ../../system/hardware/time.nix # Network time sync
      ../../system/hardware/opengl.nix
      ../../system/hardware/gpu-monitoring.nix # GPU monitoring tools
      ../../system/hardware/printing.nix
      # ../../system/hardware/bluetooth.nix
      ../../system/security/sudo.nix
      ../../system/security/gpg.nix
      ../../system/security/blocklist.nix
      ../../system/security/firewall.nix
      ../../system/security/firejail.nix
      # ../../system/style/stylix.nix
      ../../system/security/autoupgrade.nix # auto upgrade
      ( import ../../system/security/sshd.nix {
        authorizedKeys = systemSettings.authorizedKeys; # SSH keys TESTING !
        inherit userSettings;
        inherit systemSettings;
        inherit lib; })
    ];

  wsl = {
    enable = true;
    automountPath = "/mnt";
    defaultUser = userSettings.username;
    startMenuLaunchers = true;

    # Enable native Docker support
    # docker-native.enable = true;

    # Enable integration with Docker Desktop (needs to be installed)
    # docker-desktop.enable = true;

  };

  # Fix nix path
  nix.nixPath = [ "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
                  "nixos-config=$HOME/.dotfiles/system/configuration.nix"
                  "/nix/var/nix/profiles/per-user/root/channels"
                ];

  # Experimental features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Ensure nix flakes are enabled
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # I'm sorry Stallman-taichou
  nixpkgs.config.allowUnfree = true;

  # Kernel modules
  boot.kernelModules = systemSettings.kernelModules;

  # Networking
  networking.hostName = systemSettings.hostname; # Define your hostname.

  # Timezone and locale
  time.timeZone = systemSettings.timezone; # time zone
  i18n.defaultLocale = systemSettings.locale;
  i18n.extraLocaleSettings = {
    LC_ADDRESS = systemSettings.locale;
    LC_IDENTIFICATION = systemSettings.locale;
    LC_MEASUREMENT = systemSettings.locale;
    LC_MONETARY = systemSettings.locale;
    LC_NAME = systemSettings.locale;
    LC_NUMERIC = systemSettings.locale;
    LC_PAPER = systemSettings.locale;
    LC_TELEPHONE = systemSettings.locale;
    LC_TIME = systemSettings.timeLocale;  # Use timeLocale for Monday as first day of week
  };

  # User account
  users.users.${userSettings.username} = {
    isNormalUser = true;
    description = userSettings.name;
    extraGroups = userSettings.extraGroups;
    packages = with pkgs; [];
    uid = 1000;
  };

  # System packages
  environment.systemPackages = systemSettings.systemPackages;

  # I use zsh btw
  environment.shells = with pkgs; [ zsh ];
  users.defaultUserShell = pkgs.zsh;
  programs.zsh.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  # It is ok to leave this unchanged for compatibility purposes
  system.stateVersion = systemSettings.systemStateVersion;

}
