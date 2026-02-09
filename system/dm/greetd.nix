{ config, lib, pkgs, systemSettings, ... }:

let
  greetdEnabled = systemSettings.greetdEnable or false;
  extraConfig = systemSettings.greetdSwayExtraConfig or "";

  # Minimal Sway config for the greeter session.
  # Sway supports per-output rotation/scale/position — cage does not.
  swayGreeterConfig = pkgs.writeText "greetd-sway-config" ''
    # Per-profile output directives (rotation, scale, position)
    ${extraConfig}

    # Launch ReGreet, then exit Sway when it's done
    exec "regreet; swaymsg exit"
  '';
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
    # Override the cage-based command set by programs.regreet with Sway.
    # Sway handles multi-monitor output configuration (rotation, scale, position)
    # which cage cannot do — cage spans one window across the bounding box of all outputs.
    settings.default_session.command = lib.mkForce
      "dbus-run-session sway --config ${swayGreeterConfig}";
  };

  # ReGreet greeter program (GTK4 greeter)
  # programs.regreet sets greetd's command to cage by default (mkDefault),
  # which we override above with mkForce to use Sway instead.
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
