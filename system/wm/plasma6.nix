{ pkgs, ... }:

{
  # Import wayland config
  imports = [ ./wayland.nix
              ./pipewire.nix
              ./fonts.nix
            ];

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;


  # # KDE Plasma 6
  # services.xserver.enable = true;
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.displayManager.sddm.wayland.enable = true; # enable if blackscreen with plasma6
  # services.desktopManager.plasma6.enable = true;
  services.xserver.displayManager.defaultSession = "plasma";
}

  # services.xserver.enable = true;
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.displayManager.sddm.wayland.enable = true; # enable if blackscreen with plasma6
  # services.xserver.displayManager.defaultSession = "plasma"; # or should be "plasmawayland" ??
  # services.desktopManager.plasma6.enable = true;