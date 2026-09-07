{ pkgs, lib, userSettings, systemSettings, ... }:

# sway-apps "always connected" monitors: force a DRM connector's status so a
# monitor switched OFF (DisplayPort drops HPD exactly like an unplugged cable)
# does not make sway destroy the output and evacuate its workspaces. Writing
# /sys/class/drm/<connector>/status needs root; this is the only privileged
# thing sway-apps does, through a tiny validating helper the user may run with
# sudo and no password. Measured on DESK 2026-09-07: with the connector forced
# on, powering the Samsung off/on moved nothing.
let
  swayEnabled = userSettings.wm == "sway" || systemSettings.enableSwayForDESK == true;
  enabled = swayEnabled && (systemSettings.swayAppsEnable or false);
  helper = pkgs.writeShellApplication {
    name = "sway-connector-force";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # usage: sway-connector-force <cardN-CONNECTOR> <on|detect|off>
      conn="''${1:-}"; mode="''${2:-}"
      case "$conn" in
        card[0-9]*-[A-Za-z]*-[0-9]*) ;;
        *) echo "bad connector name: $conn" >&2; exit 2 ;;
      esac
      case "$mode" in on|detect|off) ;; *) echo "mode must be on|detect|off" >&2; exit 2 ;; esac
      f="/sys/class/drm/$conn/status"
      [ -f "$f" ] || { echo "no such connector: $conn" >&2; exit 3; }
      printf '%s\n' "$mode" > "$f"
      echo "$conn: $(cat "$f") (force=$mode)"
    '';
  };
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = [ helper ];
    security.sudo.extraRules = [
      {
        users = [ userSettings.username ];
        commands = [
          {
            command = "/run/current-system/sw/bin/sway-connector-force";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];
  };
}
