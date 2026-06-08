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
  # Native path routes through one setup script (init + rearrange + group-0
  # orphan sweep) so logic lives in the script, not the user-managed config.
  swaysomeExecLines =
    if nativeGroups then ''
  exec $HOME/.config/sway/scripts/swaysome-groups-setup.sh''
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
            # Collapse all legacy swaysome exec lines (per-command init/rearrange,
            # the focus-fragile assign script, and any earlier orphan-sweep) into
            # the single consolidated setup script. Deletions are idempotent.
            ${pkgs.gnused}/bin/sed -i \
              -e '/exec swaysome /d' \
              -e '/swaysome-assign-groups/d' \
              -e '/swaysome-sweep-orphans/d' \
              "$KANSHI_CONFIG"
            # Ensure the consolidated setup runs after outputs are enabled.
            if ${pkgs.gnugrep}/bin/grep -qE 'output \* enable' "$KANSHI_CONFIG" \
               && ! ${pkgs.gnugrep}/bin/grep -q 'swaysome-groups-setup' "$KANSHI_CONFIG"; then
              ${pkgs.gnused}/bin/sed -i '/output \* enable/a\  exec $HOME/.config/sway/scripts/swaysome-groups-setup.sh' "$KANSHI_CONFIG"
            fi
          fi
        '';
    })
  ];
}
