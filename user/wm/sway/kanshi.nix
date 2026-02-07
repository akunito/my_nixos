{ config, pkgs, lib, systemSettings, ... }:

let
  # Declarative mode: Nix manages kanshi config
  declarativeMode = (systemSettings.swayKanshiSettings or null) != null
                    && !(systemSettings.kanshiImperativeMode or false);

  # Imperative mode: User manages ~/.config/kanshi/config directly
  imperativeMode = systemSettings.kanshiImperativeMode or false;

  # Either mode enables kanshi
  kanshiEnabled = declarativeMode || imperativeMode;
in
{
  config = lib.mkMerge [
    # Common kanshi config for both modes
    (lib.mkIf kanshiEnabled {
      services.kanshi = {
        enable = true;
        systemdTarget = "sway-session.target";
      };

      # Restart kanshi after HM activation if in a Sway session
      home.activation.kanshiReapplyAfterSwitch =
        lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
          if ${pkgs.swayfx}/bin/swaymsg -t get_version >/dev/null 2>&1; then
            ${pkgs.systemd}/bin/systemctl --user reset-failed kanshi.service >/dev/null 2>&1 || true
            ${pkgs.systemd}/bin/systemctl --user restart kanshi.service >/dev/null 2>&1 || true
          fi
        '';
    })

    # Declarative mode - Nix manages the config
    (lib.mkIf declarativeMode {
      services.kanshi.settings = systemSettings.swayKanshiSettings;

      # Ensure Home Manager owns kanshi config robustly
      xdg.configFile."kanshi/config".force = true;
    })

    # Imperative mode - User manages ~/.config/kanshi/config directly
    (lib.mkIf imperativeMode {
      # Create a default config if none exists
      home.activation.kanshiCreateDefaultConfig =
        lib.hm.dag.entryBefore [ "kanshiReapplyAfterSwitch" ] ''
          KANSHI_CONFIG="$HOME/.config/kanshi/config"
          if [ ! -f "$KANSHI_CONFIG" ]; then
            mkdir -p "$(dirname "$KANSHI_CONFIG")"
            cat > "$KANSHI_CONFIG" << 'EOF'
# Kanshi Configuration (User-Managed)
# Edit this file directly or use nwg-displays to configure outputs
#
# Example profile:
# profile {
#   output eDP-1 mode 1920x1080 position 0,0
#   output HDMI-A-1 mode 1920x1080 position 1920,0
# }

# Default profile - enable all outputs
profile default-auto {
  output * enable
  exec swaysome init 1
  exec swaysome rearrange-workspaces
  exec $HOME/.config/sway/scripts/swaysome-assign-groups.sh
}
EOF
          fi
        '';
    })
  ];
}
