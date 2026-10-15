{ pkgs, pkgs-unstable, lib, userSettings, storageDriver ? null, userlandProxy ? true
, buildCacheMax ? "20GB", buildCacheReserved ? "5GB", ... }:

let
  reap = import ../../lib/docker-image-reap.nix { inherit pkgs; docker = pkgs-unstable.docker; };
in

assert lib.asserts.assertOneOf "storageDriver" storageDriver [
  null
  "aufs"
  "btrfs"
  "devicemapper"
  "overlay"
  "overlay2"
  "zfs"
];

{
  virtualisation.docker = lib.mkIf (userSettings.dockerEnable == true) {
    enable = true;
    # dockerRootRequiresSudo (workstations, AINF-407): the root daemon is the
    # exception, not the default — socket-activated only when someone runs
    # `sudo docker`. docker.socket stays enabled either way.
    enableOnBoot = !(userSettings.dockerRootRequiresSudo or false);
    # Track docker from pkgs-unstable so we don't have to bump pins each time
    # the stable channel's default docker is flagged unmaintained.
    package = pkgs-unstable.docker;
    storageDriver = storageDriver;
    # Off on purpose — replaced by the docker-image-prune timer below.
    #
    # autoPrune runs `docker system prune -f`, which also deletes every STOPPED
    # container and unused network. On a development machine that means the
    # compose stacks you left down overnight are gone by Monday (harmless for
    # data — named volumes and tagged images are untouched — but you have to
    # `compose up` again). `docker image prune -f` reclaims the same disk that
    # actually grows, without touching containers.
    #
    # It also only ever applied to the ROOT daemon: hosts running rootless
    # docker got nothing from it. See profiles/vps/base.nix and
    # profiles/homelab/base.nix for the rootless equivalents.
    autoPrune.enable = false;
    liveRestore = true; # Fix for https://discourse.nixos.org/t/docker-hanging-on-reboot/18270/3
                        # Allow dockerd to be restarted without affecting running container.
                        # This option is incompatible with docker swarm.

    # userland-proxy = false routes published ports through DNAT/FORWARD only,
    # instead of ALSO spawning a docker-proxy process bound to 0.0.0.0:<port>
    # on the host. That matters for firewalling: docker-proxy traffic is
    # delivered locally via INPUT, where the DOCKER-USER chain has no say, so a
    # host firewall that trusts an interface (e.g. tailscale0) hands out every
    # published container port on it. With the proxy off, DOCKER-USER is the
    # single choke point — see system/security/docker-firewall.nix.
    #
    # Only affects containers started after the next daemon restart.
    #
    # autoPrune above reaps dangling images and cache, but nothing bounds the
    # in-use build cache — see lib/docker-buildkit-gc.nix for why that matters.
    daemon.settings =
      (import ../../lib/docker-buildkit-gc.nix {
        max = buildCacheMax;
        reserved = buildCacheReserved;
      })
      // lib.optionalAttrs (!userlandProxy) {
        userland-proxy = false;
      };
  };
  # Image reaper for the root daemon — the autoPrune replacement, same Monday 00:00 slot.
  # Dangling images, tagged images unused for 30 days (protect list in
  # lib/docker-image-reap.nix), build cache unused for 7 days. Volumes, networks and stopped
  # containers are left alone, and dockerd refuses to delete an image any container still
  # references. builder.gc above still caps the cache size between runs.
  systemd.timers.docker-image-prune = lib.mkIf (userSettings.dockerEnable == true) {
    description = "Weekly Docker image reaper";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon *-*-* 00:00:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };
  systemd.services.docker-image-prune = lib.mkIf (userSettings.dockerEnable == true) {
    description = "Remove dangling and old unused Docker images and build cache";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${reap}/bin/docker-image-reap";
    };
  };

  # The docker group is root-equivalent (any process of the user can mount / into
  # a container). With dockerRootRequiresSudo the user stays out of it and the
  # root daemon is reached through sudo only.
  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.dockerEnable == true && !(userSettings.dockerRootRequiresSudo or false)) [ "docker" ];
  environment.systemPackages = lib.mkIf (userSettings.dockerEnable == true) [
    pkgs-unstable.docker
    pkgs-unstable.docker-compose
    pkgs.lazydocker
    reap # `sudo docker-image-reap --dry-run` lists what the next run would remove
  ];
}
