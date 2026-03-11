{ pkgs, systemSettings, userSettings, lib, ... }:

# Homelab Docker Stacks - Systemd service to start docker-compose stacks on boot
# Enable with homelabDockerEnable = true in profile config
#
# Two modes:
# 1. Hardcoded stacks (homelabDockerStacks = []): Legacy LXC_HOME/LXC_matrix behavior
# 2. Configurable stacks (homelabDockerStacks != []): VPS and new profiles
#
# Two Docker modes:
# 1. Root Docker (dockerRootlessEnable = false): Runs as root, requires docker.service
# 2. Rootless Docker (dockerRootlessEnable = true): Runs as user, requires user@1000.service

let
  homelabDir = "/home/${userSettings.username}/.homelab";
  isRootless = userSettings.dockerRootlessEnable or false;
  configStacks = systemSettings.homelabDockerStacks or [];
  useConfigStacks = configStacks != [];

  dockerCompose = "${pkgs.docker-compose}/bin/docker-compose";

  # Rootless Docker environment
  rootlessEnv = [
    "DOCKER_HOST=unix:///run/user/1000/docker.sock"
    "XDG_RUNTIME_DIR=/run/user/1000"
    "PATH=${pkgs.docker}/bin:${pkgs.docker-compose}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
  ];

  # === Configurable stacks mode ===
  configStartScript = pkgs.writeShellScript "homelab-docker-start" ''
    echo "Starting homelab docker stacks..."
    FAILED=""
    ${lib.concatMapStringsSep "\n" (stack: ''
      echo "Starting ${stack.name} stack..."
      if ! ${dockerCompose} -f ${homelabDir}/${stack.path}/docker-compose.yml up -d; then
        echo "WARNING: ${stack.name} stack failed to start"
        FAILED="$FAILED ${stack.name}"
      fi
    '') configStacks}
    if [ -n "$FAILED" ]; then
      echo "WARNING: These stacks failed to start:$FAILED"
    fi
    echo "All homelab docker stacks processed."
  '';

  configStopScript = pkgs.writeShellScript "homelab-docker-stop" ''
    echo "Stopping homelab docker stacks..."
    ${lib.concatMapStringsSep "\n" (stack: ''
      ${dockerCompose} -f ${homelabDir}/${stack.path}/docker-compose.yml down || true
    '') (lib.reverseList configStacks)}
    echo "All homelab docker stacks stopped."
  '';

  # === Hardcoded stacks mode (backward compat) ===
  hardcodedStartScript = pkgs.writeShellScript "homelab-docker-start" ''
    set -e
    echo "Starting homelab docker stacks..."

    # Homelab stack - start dependencies first, then services
    echo "Starting homelab stack (nextcloud, syncthing, freshrss, etc.)..."
    ${dockerCompose} -f ${homelabDir}/homelab/docker-compose.yml up -d

    # Media stack
    echo "Starting media stack..."
    ${dockerCompose} -f ${homelabDir}/media/docker-compose.yml up -d

    # Nginx proxy
    echo "Starting nginx-proxy stack..."
    ${dockerCompose} -f ${homelabDir}/nginx-proxy/docker-compose.yml up -d

    # Unifi
    echo "Starting unifi stack..."
    ${dockerCompose} -f ${homelabDir}/unifi/docker-compose.yml up -d

    echo "All homelab docker stacks started."
  '';

  hardcodedStopScript = pkgs.writeShellScript "homelab-docker-stop" ''
    echo "Stopping homelab docker stacks..."
    ${dockerCompose} -f ${homelabDir}/unifi/docker-compose.yml down || true
    ${dockerCompose} -f ${homelabDir}/nginx-proxy/docker-compose.yml down || true
    ${dockerCompose} -f ${homelabDir}/media/docker-compose.yml down || true
    ${dockerCompose} -f ${homelabDir}/homelab/docker-compose.yml down || true
    echo "All homelab docker stacks stopped."
  '';

  startScript = if useConfigStacks then configStartScript else hardcodedStartScript;
  stopScript = if useConfigStacks then configStopScript else hardcodedStopScript;
in
{
  config = lib.mkIf (systemSettings.homelabDockerEnable or false) {
    systemd.services.homelab-docker = {
      description = "Homelab Docker Stacks";
      after = if isRootless
        then [ "user@1000.service" "network-online.target" ]
        else [ "docker.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = if isRootless
        then [ "user@1000.service" ]
        else [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = startScript;
        ExecStop = stopScript;
        User = if isRootless then userSettings.username else "root";
        TimeoutStartSec = "5min";
        TimeoutStopSec = "2min";
      } // lib.optionalAttrs isRootless {
        Environment = rootlessEnv;
        # SEC-DOCKER-HARD-002: Systemd hardening for rootless Docker service
        ProtectSystem = "strict";
        ReadWritePaths = [ homelabDir "/run/user/1000" "/home/${userSettings.username}/.local/share/docker" "/home/${userSettings.username}/.config/docker" "/tmp" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        LockPersonality = true;
        RestrictRealtime = true;
      };
    };
  };
}
