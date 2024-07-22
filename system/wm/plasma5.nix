{ inputs, pkgs, lib, ... }: let
  pkgs-hyprland = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  # Import wayland config
  imports = [ ./wayland.nix
              ./pipewire.nix
            ];

  # Security >>Probably not needed with KDE Plasma
  # security = {
  #   pam.services.login.enableGnomeKeyring = true;
  # };

  # services.gnome.gnome-keyring.enable = true;

  # Enable Plasma5
  services.xserver.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;
  services.xserver.displayManager.defaultSession = "plasmawayland";