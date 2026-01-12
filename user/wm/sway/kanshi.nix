{ config, pkgs, lib, systemSettings, ... }:

let
  enabled = (systemSettings.swayKanshiSettings or null) != null;
in
{
  config = lib.mkIf enabled {
    # Official/standard dynamic output configuration for Sway/SwayFX (wlroots): kanshi.
    #
    # IMPORTANT:
    # - This must not affect Plasma 6.
    # - We only enable kanshi when the active profile provides `systemSettings.swayKanshiSettings`.
    # - The kanshi systemd unit is bound to sway-session.target (Sway-only).
    services.kanshi = {
      enable = true;
      systemdTarget = "sway-session.target";
      settings = systemSettings.swayKanshiSettings;
    };

    # Ensure Home Manager owns kanshi config robustly (only when kanshi is enabled for this profile).
    xdg.configFile."kanshi/config".force = true;

    # CRITICAL: Home-Manager activation reloads systemd --user and can coincide with compositor state changes.
    # On this setup, output layout can revert to defaults right after `sync-user.sh`.
    # Fix: after HM activation reloads systemd, restart kanshi *only if we're in a real Sway session*,
    # so the configured output layout is re-applied deterministically.
    home.activation.kanshiReapplyAfterSwitch =
      lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
        # Only reapply in an actual live Sway session.
        if ${pkgs.swayfx}/bin/swaymsg -t get_version >/dev/null 2>&1; then
          ${pkgs.systemd}/bin/systemctl --user reset-failed kanshi.service >/dev/null 2>&1 || true
          ${pkgs.systemd}/bin/systemctl --user restart kanshi.service >/dev/null 2>&1 || true
        fi
      '';
  };
}


