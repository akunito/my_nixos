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

  # xdg-desktop-portal-wlr ScreenCast output picker (Sway screen sharing).
  # Its built-in "default" chooser shells out to `slurp` (found on PATH) to let
  # you click which monitor to share. But the systemd user service runs with a
  # restricted PATH that omits slurp, so the picker silently fails: selecting a
  # monitor does nothing and Vesktop/Discord/OBS never start sharing. Put slurp
  # on the service PATH so the default chooser works.
  # NOTE: we deliberately do NOT set chooser_cmd + chooser_type=simple — xdph
  # 0.8.0's generic "simple" parser fails to match a bare output name ("selected
  # unknown target: DP-1"); the hardcoded default chooser parses correctly.
  systemd.user.services.xdg-desktop-portal-wlr.path = [ pkgs.slurp ];

  # Ensure KDE frameworks are available for the portal
  environment.systemPackages = with pkgs; [
    kdePackages.kio # KDE I/O framework for file operations
    kdePackages.kio-extras # Additional KIO protocols
    adwaita-qt # Qt5 Adwaita style
    adwaita-qt6 # Qt6 Adwaita style (CRITICAL for KDE portal dark mode)
  ];
}
