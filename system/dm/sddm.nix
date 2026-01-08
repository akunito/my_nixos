{ config, lib, ... }:

{
  # KWallet PAM integration for automatic wallet unlocking on login
  # This enables KWallet to unlock automatically when logging in through SDDM
  # Works for any window manager that uses SDDM (Plasma, Sway, Hyprland, etc.)
  # The module is self-aware - it checks if SDDM is enabled rather than checking specific WMs
  security.pam.services = lib.mkIf config.services.displayManager.sddm.enable {
    login.enableKwallet = true;      # Unlock wallet on TTY/login
    sddm.enableKwallet = true;       # Unlock wallet on SDDM login (primary for graphical sessions)

    # IMPORTANT: NixOS' default PAM rule ordering places the `kwallet` auth rule
    # before the `unix` rule that actually collects the user's password.
    #
    # In practice this can cause kwallet-pam to see an empty/incorrect authtok,
    # even when the user typed the correct password at SDDM, leading to:
    #   ksecretd: Failed to open wallet "kdewallet" "Read error - possibly incorrect password."
    #
    # Reorder `kwallet` auth to run AFTER `unix` so it can use the collected password.
    #
    # NOTE: `rules.*` is an experimental NixOS option; keep this scoped to DESK SDDM.
    login.rules.auth.kwallet.order = config.security.pam.services.login.rules.auth.unix.order + 10;
  };
}

