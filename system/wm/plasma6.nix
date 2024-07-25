{ pkgs, ... }:

{
  # Import wayland config
  imports = [ ./wayland.nix
              ./pipewire.nix
              ./fonts.nix
            ];

  # KDE Plasma 6
  services.xserver = {
    enable = true;
    displayManager.displayManager.sddm.enable = true;
    desktopManager.displayManager.sddm.wayland.enable = true; # enable if blackscreen with plasma6
    displayManager.defaultSession = "plasmawayland"; # or should be "plasmawayland" ??
  };
  services.desktopManager = {
    plasma6.enable = true;
  };
}

  # services.xserver.enable = true;
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.displayManager.sddm.wayland.enable = true; # enable if blackscreen with plasma6
  # services.desktopManager.plasma6.enable = true;
  # services.xserver.displayManager.defaultSession = "plasma"; # or should be "plasmawayland" ??