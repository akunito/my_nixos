{ pkgs, systemSettings, lib, ... }:

# Homelab Docker Stacks - Systemd service to start docker-compose stacks on boot
# Enable with homelabDockerEnable = true in profile config

let
  homelabDir = "/home/akunito/.homelab";

  # Script to start all homelab docker stacks with proper ordering
  startScript = pkgs.writeShellScript "homelab-docker-start" ''
    set -e
    echo "Starting homelab docker stacks..."

    # Homelab stack - start dependencies first, then services
    echo "Starting homelab stack (nextcloud, syncthing, freshrss, etc.)..."
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/homelab/docker-compose.yml up -d

    # Media stack
    echo "Starting media stack..."
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/media/docker-compose.yml up -d

    # Nginx proxy
    echo "Starting nginx-proxy stack..."
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/nginx-proxy/docker-compose.yml up -d

    # Unifi
    echo "Starting unifi stack..."
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/unifi/docker-compose.yml up -d

    echo "All homelab docker stacks started."
  '';

  stopScript = pkgs.writeShellScript "homelab-docker-stop" ''
    echo "Stopping homelab docker stacks..."
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/unifi/docker-compose.yml down || true
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/nginx-proxy/docker-compose.yml down || true
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/media/docker-compose.yml down || true
    ${pkgs.docker-compose}/bin/docker-compose -f ${homelabDir}/homelab/docker-compose.yml down || true
    echo "All homelab docker stacks stopped."
  '';
in
{
  config = lib.mkIf (systemSettings.homelabDockerEnable or false) {
    systemd.services.homelab-docker = {
      description = "Homelab Docker Stacks";
      after = [ "docker.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = startScript;
        ExecStop = stopScript;
        # Run as root to ensure docker access
        User = "root";
        # Give containers time to initialize
        TimeoutStartSec = "5min";
        TimeoutStopSec = "2min";
      };
    };
  };
}
