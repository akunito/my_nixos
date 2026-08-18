{ pkgs, pkgs-unstable, lib, userSettings, storageDriver ? null, userlandProxy ? true, ... }:

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
    enableOnBoot = true;
    # Track docker from pkgs-unstable so we don't have to bump pins each time
    # the stable channel's default docker is flagged unmaintained.
    package = pkgs-unstable.docker;
    storageDriver = storageDriver;
    # NOTE: this only ever prunes the ROOT daemon. Hosts running rootless docker
    # (VPS_PROD sets dockerEnable = false) get nothing from it — they need their
    # own build-cache cap and prune timer; see profiles/vps/base.nix.
    autoPrune.enable = true;
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
    daemon.settings = lib.mkIf (!userlandProxy) {
      userland-proxy = false;
    };
  };
  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.dockerEnable == true) [ "docker" ];
  environment.systemPackages = lib.mkIf (userSettings.dockerEnable == true) [
    pkgs-unstable.docker
    pkgs-unstable.docker-compose
    pkgs.lazydocker
  ];
}
