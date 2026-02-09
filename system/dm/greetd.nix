{ config, lib, pkgs, systemSettings, ... }:

let
  greetdEnabled = systemSettings.greetdEnable or false;
in
{
  # KWallet PAM integration for automatic wallet unlocking on login
  # This enables KWallet to unlock automatically when logging in through greetd
  security.pam.services = lib.mkIf greetdEnabled {
    login.enableKwallet = true;   # Unlock wallet on TTY/login
    greetd.enableKwallet = true;  # Unlock wallet on greetd login (primary for graphical sessions)
  };

  # greetd display manager
  services.greetd = lib.mkIf greetdEnabled {
    enable = true;
  };

  # ReGreet greeter program (GTK4 greeter)
  # programs.regreet sets greetd's command to cage by default
  programs.regreet = lib.mkIf greetdEnabled {
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
  environment.etc."greetd/regreet.css" = lib.mkIf greetdEnabled {
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
