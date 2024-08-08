{ pkgs, ... }:

{
  # Import wayland config
  imports = [ ./wayland.nix
              ./pipewire.nix
              ./fonts.nix
              ./dbus.nix
            ];

  # Enable Plasma5
  services.xserver = {
    enable = true;
    displayManager.sddm.enable = true;
    desktopManager.plasma5.enable = true;
    displayManager.defaultSession = "plasmawayland"; # or should be "plasmawayland" ??
  };
}

  # services.xserver.enable = true;
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.desktopManager.plasma5.enable = true;
  # services.xserver.displayManager.defaultSession = "plasma"; # or should be "plasmawayland" ??