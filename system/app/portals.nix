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
      xdg-desktop-portal-wlr # Sway ScreenCast/Screenshot
    ];

    # Configure portal preferences
    # Set KDE as default for all desktops
    config = {
      # For Plasma6
      plasma = {
        default = "kde";
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.Settings" = "gtk"; # Use GTK for dark mode
      };
      # For Sway/SwayFX - use mkForce to override Sway module's gtk default
      sway = {
        default = lib.mkForce "kde";
        "org.freedesktop.impl.portal.FileChooser" = lib.mkForce "kde"; # Dolphin-style picker
        "org.freedesktop.impl.portal.Settings" = lib.mkForce "gtk"; # Dark mode from GTK/dconf
        "org.freedesktop.impl.portal.ScreenCast" = lib.mkForce "wlr"; # wlroots native
        "org.freedesktop.impl.portal.Screenshot" = lib.mkForce "wlr"; # wlroots native
      };
      # Fallback for any other desktop
      common = {
        default = "kde";
        "org.freedesktop.impl.portal.FileChooser" = "kde";
        "org.freedesktop.impl.portal.Settings" = "gtk"; # Use GTK for dark mode
      };
    };

    # CRITICAL: Do NOT force xdg-open to use portal
    # This causes file opening to fail because the portal doesn't read mimeapps.list
    # GTK apps will still use the portal for file chooser dialogs, but xdg-open will work directly
    xdgOpenUsePortal = false;
  };

  # Ensure KDE frameworks are available for the portal
  environment.systemPackages = with pkgs; [
    kdePackages.kio # KDE I/O framework for file operations
    kdePackages.kio-extras # Additional KIO protocols
    adwaita-qt # Qt5 Adwaita style
    adwaita-qt6 # Qt6 Adwaita style (CRITICAL for KDE portal dark mode)
  ];
}
