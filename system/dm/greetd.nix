{ config, lib, pkgs, systemSettings, ... }:

{
  # KWallet PAM integration for automatic wallet unlocking on login
  # This enables KWallet to unlock automatically when logging in through greetd
  security.pam.services = lib.mkIf (systemSettings.greetdEnable or false) {
    login.enableKwallet = true;   # Unlock wallet on TTY/login
    greetd.enableKwallet = true;  # Unlock wallet on greetd login (primary for graphical sessions)
  };

  services.greetd = lib.mkIf (systemSettings.greetdEnable or false) {
    enable = true;
    settings = {
      default_session = let
        # If there's a setup script (e.g., monitor rotation), wrap ReGreet with it
        hasSetupScript = (systemSettings.sddmSetupScript or null) != null;
        rotationScript = pkgs.writeShellScript "greetd-rotation" ''
          ${systemSettings.sddmSetupScript or ""}
          exec ${pkgs.greetd.regreet}/bin/regreet
        '';
      in {
        command = if hasSetupScript
                  then "${rotationScript}"
                  else "${pkgs.regreet}/bin/regreet";
      };
    };
  };

  # ReGreet greeter program
  programs.regreet = lib.mkIf (systemSettings.greetdEnable or false) {
    enable = true;
    settings = {
      background = {
        path = "${systemSettings.background-package}";
        fit = "Cover";
      };
      appearance = {
        greeting_msg = "Welcome back!";
      };
    };
  };

  # CSS theming
  environment.etc."greetd/regreet.css" = lib.mkIf (systemSettings.greetdEnable or false) {
    text = ''
      /* ReGreet CSS Theming */
      window {
        background: rgba(30, 30, 46, 0.95);
      }

      button {
        border-radius: 8px;
        padding: 8px 16px;
        transition: all 200ms ease;
      }

      button:hover {
        background: rgba(137, 180, 250, 0.2);
      }

      entry {
        border-radius: 8px;
        padding: 8px;
        border: 1px solid rgba(137, 180, 250, 0.3);
      }

      entry:focus {
        border-color: rgba(137, 180, 250, 0.8);
      }
    '';
  };
}
