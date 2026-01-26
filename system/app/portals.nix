{
  pkgs,
  lib,
  systemSettings,
  userSettings,
  ...
}:

{
  # XDG Desktop Portal Configuration
  # This configures which portal backend to use for file pickers and other integrations

  xdg.portal = {
    enable = true;

    # Use KDE portal as the primary backend
    # This gives us Dolphin-style file picker with path bar visible
    extraPortals = with pkgs; [
      kdePackages.xdg-desktop-portal-kde
      xdg-desktop-portal-gtk # Keep as fallback
    ];

    # Configure portal preferences
    # Set KDE as default for all desktops
    config = {
      # For Plasma6
      plasma = {
        default = "kde";
        "org.freedesktop.impl.portal.FileChooser" = "kde";
      };
      # For Sway/SwayFX - use mkForce to override Sway module's gtk default
      sway = {
        default = lib.mkForce "kde";
        "org.freedesktop.impl.portal.FileChooser" = lib.mkForce "kde";
      };
      # Fallback for any other desktop
      common = {
        default = "kde";
        "org.freedesktop.impl.portal.FileChooser" = "kde";
      };
    };

    # CRITICAL: Force xdg-open to use portal
    # This ensures GTK apps like Bottles will use the portal
    xdgOpenUsePortal = true;
  };

  # Ensure KDE frameworks are available for the portal
  environment.systemPackages = with pkgs; [
    kdePackages.kio # KDE I/O framework for file operations
    kdePackages.kio-extras # Additional KIO protocols
  ];
}
