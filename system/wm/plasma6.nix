{ pkgs, lib, userSettings, ... }:

{
  # Import wayland config
  imports = [ # ./wayland.nix
              ./pipewire.nix
              ./fonts.nix
              ./dbus.nix
              #./gnome-keyring.nix
            ]
    ++ lib.optional userSettings.wmEnableHyprland (./. + "/hyprland.nix");

  # # Security
  # security = {
  #   pam.services.login.enableGnomeKeyring = true;
  # };
  # services.gnome.gnome-keyring.enable = true;

  # # KDE Plasma 6
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.wayland.enable = true; # enable if blackscreen with plasma6
  services.displayManager.defaultSession = "plasma";
 
  # # Enable the X11 windowing system.
  # # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;
  programs.xwayland.enable = true;

}