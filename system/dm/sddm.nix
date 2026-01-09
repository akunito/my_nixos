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
}

