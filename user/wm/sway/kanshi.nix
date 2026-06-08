{ config, pkgs, lib, systemSettings, ... }:

let
  # Declarative mode: Nix manages kanshi config
  declarativeMode = (systemSettings.swayKanshiSettings or null) != null
                    && !(systemSettings.kanshiImperativeMode or false);

  # Imperative mode: User manages ~/.config/kanshi/config directly
  imperativeMode = systemSettings.kanshiImperativeMode or false;

  # Native swaysome groups (laptops): rely on swaysome's own init+rearrange for
  # per-output workspace groups. The focus-based swaysome-assign-groups.sh is
  # dropped because, under `focus_follows_mouse`, its `focus output X` races and
  # corrupts swaysome's clean per-monitor assignment (spurious groups, monitors
  # left without a usable group). swaysome init/rearrange are focus-immune.
  # DESK keeps the legacy path (flag false) so its current groups are untouched.
  nativeGroups = systemSettings.swaysomeNativeGroups or false;

  # swaysome exec lines for the imperative kanshi default-auto profile.
  swaysomeExecLines =
    if nativeGroups then ''
  exec swaysome init 1
  exec swaysome rearrange-workspaces''
    else ''
  exec swaysome init 1
  exec swaysome rearrange-workspaces
  exec $HOME/.config/sway/scripts/swaysome-assign-groups.sh'';

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
${swaysomeExecLines}
}
EOF
          fi
        '';
    })

    # Native swaysome groups (laptops): migrate existing live kanshi configs to
    # the focus-immune path — drop the focus-fragile assign-groups.sh exec and
    # ensure `swaysome init` runs. Idempotent. Gated on the flag so DESK's live
    # config is never touched.
    (lib.mkIf (imperativeMode && nativeGroups) {
      home.activation.kanshiMigrateNativeGroups =
        lib.hm.dag.entryBefore [ "kanshiReapplyAfterSwitch" ] ''
          KANSHI_CONFIG="$HOME/.config/kanshi/config"
          if [ -f "$KANSHI_CONFIG" ]; then
            # Remove the focus-fragile assign script (corrupts assignment under
            # focus_follows_mouse).
            ${pkgs.gnused}/bin/sed -i '/swaysome-assign-groups/d' "$KANSHI_CONFIG"
            # Ensure swaysome init runs (re-add if a prior migration stripped it).
            if ${pkgs.gnugrep}/bin/grep -qE 'exec swaysome rearrange-workspaces' "$KANSHI_CONFIG" \
               && ! ${pkgs.gnugrep}/bin/grep -qE 'exec swaysome init' "$KANSHI_CONFIG"; then
              ${pkgs.gnused}/bin/sed -i '/exec swaysome rearrange-workspaces/i\  exec swaysome init 1' "$KANSHI_CONFIG"
            fi
          fi
        '';
    })
  ];
}
