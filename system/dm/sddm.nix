{ config, lib, ... }:

{
  # KWallet PAM integration for automatic wallet unlocking on login
  # This enables KWallet to unlock automatically when logging in through SDDM
  # Works for any window manager that uses SDDM (Plasma, Sway, Hyprland, etc.)
  # The module is self-aware - it checks if SDDM is enabled rather than checking specific WMs
  security.pam.services = lib.mkIf config.services.displayManager.sddm.enable {
    login.enableKwallet = true;      # Unlock wallet on TTY/login
    sddm.enableKwallet = true;       # Unlock wallet on SDDM login (primary for graphical sessions)
  };

  # Keep NumLock enabled by default at the login screen (and thus at session start).
  # SDDM option name is `General/Numlock` with values: "on", "off", or "none".
  services.displayManager.sddm.settings = lib.mkIf config.services.displayManager.sddm.enable {
    General = {
      Numlock = "on";
    };
  };
}

