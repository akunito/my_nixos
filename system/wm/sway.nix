{ pkgs, lib, userSettings, systemSettings, ... }:

{
  # Import shared dependencies
  imports = [
    ./wayland.nix
    ./pipewire.nix
    ./fonts.nix
    ./dbus.nix
    ../dm/sddm.nix  # Shared SDDM configuration (KWallet PAM)
    ./keyd.nix  # Keyboard remapping (Caps Lock to Hyper)
  ];

  # CRITICAL: Use swayfx instead of standard sway
  programs.sway = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    enable = true;
    package = pkgs.swayfx;  # Use SwayFX for blur, shadows, rounded corners
    extraPackages = with pkgs; [
      swaylock-effects  # Elegant lock screen with blurred screenshot
      swayidle          # Idle daemon for screen locking
      xwayland          # XWayland support for compatibility
    ];
  };

  # SDDM session configuration - allow both Plasma and SwayFX
  services.displayManager.sddm = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    enable = true;
    wayland.enable = true;
  };

  # Set Sway as default SDDM session for DESK
  # This takes precedence over Plasma default when both are enabled
  services.displayManager.defaultSession = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) "sway";

  # CRITICAL: Force Electron apps to native Wayland mode
  environment.variables = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    NIXOS_OZONE_WL = "1";
  };

  # CRITICAL: xdg-desktop-portal-wlr systemd service
  # The xdg.portal.wlr.enable option doesn't create the service properly
  # We need to manually create the systemd user service
  systemd.user.services.xdg-desktop-portal-wlr = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    description = "Portal service (wlroots implementation)";
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    
    serviceConfig = {
      Type = "dbus";
      BusName = "org.freedesktop.impl.portal.desktop.wlr";
      # Clear any existing ExecStart first (from overrides.conf), then set ours
      ExecStart = [
        ""  # This clears the existing ExecStart
        "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr"
      ];
      Restart = "on-failure";
    };
  };

  # Polkit authentication agent (needed for GUI admin apps)
  security.polkit.enable = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) true;
  
  # Polkit-gnome authentication agent
  systemd.user.services.polkit-gnome-authentication-agent-1 = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    description = "polkit-gnome-authentication-agent-1";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };

  # XWayland support for compatibility
  programs.xwayland.enable = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) true;

  # KWallet PAM integration for Sway-specific screen unlock
  # Note: login and sddm KWallet settings are now handled by ../dm/sddm.nix
  security.pam.services = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    swaylock.enableKwallet = true;   # Unlock wallet on screen unlock (Sway-specific)
  };

  # TODO: Remove later - GNOME Keyring removed in favor of KWallet to prevent conflicts
  # GNOME Keyring for Vivaldi and other apps that need secure credential storage
  # services.gnome.gnome-keyring.enable = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) true;
  # security.pam.services.login.enableGnomeKeyring = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) true;

  # Keyboard input configuration for polyglot typing (English/Spanish)
  # This will be configured in the Sway config file, but we ensure xkb is available
  # Use mkForce to override the variant from wayland.nix when Sway is enabled
  services.xserver = lib.mkIf (userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true) {
    enable = true;
    xkb = {
      layout = "us";
      variant = lib.mkForce "altgr-intl";  # US International (AltGr Dead Keys) for English/Spanish hybrid
    };
  };
}

