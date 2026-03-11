{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  systemSettings,
  userSettings,
  ...
}:

let
  # Colima settings - can be overridden in profile config
  colimaSettings = userSettings.colima or {
    cpu = 4;
    memory = 8;
    disk = 100;
    vmType = "vz";  # vz (Virtualization.framework) or qemu
    mountType = "virtiofs";  # virtiofs (fast) or sshfs (compatible)
  };

  # Generate colima.yaml content
  colimaYaml = ''
    # Colima configuration - managed by Nix
    # Do not edit directly, changes will be overwritten
    # Edit in ~/.dotfiles/user/app/colima/colima.nix

    # Number of CPUs
    cpu: ${toString colimaSettings.cpu}

    # Memory in GiB
    memory: ${toString colimaSettings.memory}

    # Disk size in GiB
    disk: ${toString colimaSettings.disk}

    # VM type (vz = Virtualization.framework, qemu = QEMU)
    vmType: ${colimaSettings.vmType}

    # Mount type (virtiofs = fast, sshfs = compatible)
    mountType: ${colimaSettings.mountType}

    # Architecture (host = match host architecture)
    arch: host

    # Runtime (docker or containerd)
    runtime: docker

    # Kubernetes (disable by default)
    kubernetes:
      enabled: false

    # Docker socket location
    docker:
      # Use default socket location
  '';

  # Startup script with proper settings
  colimaStartScript = pkgs.writeShellScriptBin "colima-start" ''
    #!/bin/bash
    # Start Colima with Nix-managed settings

    echo "Starting Colima with:"
    echo "  CPU: ${toString colimaSettings.cpu}"
    echo "  Memory: ${toString colimaSettings.memory}GB"
    echo "  Disk: ${toString colimaSettings.disk}GB"
    echo "  VM Type: ${colimaSettings.vmType}"
    echo ""

    ${pkgs.colima}/bin/colima start \
      --cpu ${toString colimaSettings.cpu} \
      --memory ${toString colimaSettings.memory} \
      --disk ${toString colimaSettings.disk} \
      --vm-type ${colimaSettings.vmType} \
      --mount-type ${colimaSettings.mountType} \
      "$@"
  '';

  colimaRestartScript = pkgs.writeShellScriptBin "colima-restart" ''
    #!/bin/bash
    # Restart Colima with Nix-managed settings

    echo "Stopping Colima..."
    ${pkgs.colima}/bin/colima stop

    echo ""
    ${colimaStartScript}/bin/colima-start "$@"
  '';

in
lib.mkIf (systemSettings.profile == "darwin") {
  # Install packages
  home.packages = [
    pkgs.colima                    # Container runtime (VM manager)
    pkgs.docker-client             # Docker CLI (client only, no daemon)
    pkgs.docker-compose            # Docker Compose v2
    colimaStartScript              # colima-start command
    colimaRestartScript            # colima-restart command
  ];

  # Note: colima.yaml is NOT managed by Home Manager because Colima needs
  # write access to it at runtime. Settings are passed via CLI flags in
  # colima-start instead, which is the source of truth.

  # Shell aliases
  programs.zsh.shellAliases = {
    # Colima management
    colima-status = "colima status";
    colima-stop = "colima stop";
    colima-ssh = "colima ssh";
    colima-logs = "colima logs";

    # Docker shortcuts (ensure using colima socket)
    docker-ps = "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'";
    docker-stats = "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'";
  };

  programs.bash.shellAliases = {
    colima-status = "colima status";
    colima-stop = "colima stop";
  };

  # Ensure DOCKER_HOST points to colima socket
  home.sessionVariables = {
    DOCKER_HOST = "unix://${config.home.homeDirectory}/.colima/default/docker.sock";
  };
}
