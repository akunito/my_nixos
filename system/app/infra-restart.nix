# infra-restart — the one write action the Infra Alerts bot may perform (AINF-368 F4)
#
# Installs `infra-restart <docker-rootless|docker-rootful> [--check]` and a
# sudoers rule so the primary user can run exactly that binary as root with no
# password. The bot (VPS, User=akunito) runs it locally with `sudo -n`, and on
# the NAS through BatchMode ssh as akunito + `sudo -n` — the VPS user's key is
# already in the NAS authorizedKeys for the AkuCraft bot.
#
# Deliberately tiny allow-list: the two docker daemons. Units are out of scope
# for now (owner decision 2026-09-11). Targets not configured on this host are
# refused, so the same binary is safe everywhere.
#
# Flag: infraRestartEnable (VPS_PROD, NAS_PROD).

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  enabled = systemSettings.infraRestartEnable or false;
  rootful = config.virtualisation.docker.enable;
  rootless = config.virtualisation.docker.rootless.enable;
  username = userSettings.username;

  script = pkgs.writeShellApplication {
    name = "infra-restart";
    runtimeInputs = with pkgs; [ coreutils systemd util-linux ];
    text = ''
      DOCKER_ROOTFUL="${lib.boolToString rootful}"
      DOCKER_ROOTLESS="${lib.boolToString rootless}"
      DOCKER_USER="${username}"
      target=''${1:-}
      mode=''${2:-}

      [ "$(id -u)" = 0 ] || { echo "infra-restart: must run as root (sudo -n infra-restart ...)"; exit 2; }

      userctl() {
        local uid; uid=$(id -u "$DOCKER_USER")
        runuser -u "$DOCKER_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" systemctl --user "$@"
      }

      case "$target" in
        docker-rootful)
          [ "$DOCKER_ROOTFUL" = true ] || { echo "docker-rootful is not configured on $(hostname)"; exit 3; }
          [ "$mode" = "--check" ] && { echo "ok: docker-rootful $(systemctl is-active docker.service)"; exit 0; }
          systemctl restart docker.service
          sleep 3
          echo "docker-rootful: $(systemctl is-active docker.service)" ;;
        docker-rootless)
          [ "$DOCKER_ROOTLESS" = true ] || { echo "docker-rootless is not configured on $(hostname)"; exit 3; }
          [ "$mode" = "--check" ] && { echo "ok: docker-rootless $(userctl is-active docker.service)"; exit 0; }
          userctl restart docker.service
          sleep 5
          echo "docker-rootless: $(userctl is-active docker.service)" ;;
        *)
          echo "usage: infra-restart docker-rootless|docker-rootful [--check]"; exit 2 ;;
      esac
    '';
  };
in
lib.mkIf enabled {
  environment.systemPackages = [ script ];

  # Match on the stable /run/current-system path (what `sudo infra-restart`
  # resolves to), not the store path, or the rule never matches.
  security.sudo.extraRules = [{
    users = [ username ];
    commands = [{
      command = "/run/current-system/sw/bin/infra-restart";
      options = [ "NOPASSWD" ];
    }];
  }];
}
