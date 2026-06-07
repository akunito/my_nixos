{ pkgs, pkgs-unstable, lib, userSettings, storageDriver ? null, ... }:

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
    autoPrune.enable = true;
    liveRestore = true; # Fix for https://discourse.nixos.org/t/docker-hanging-on-reboot/18270/3
                        # Allow dockerd to be restarted without affecting running container.
                        # This option is incompatible with docker swarm.
  };
  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.dockerEnable == true) [ "docker" ];
  environment.systemPackages = lib.mkIf (userSettings.dockerEnable == true) [
    pkgs-unstable.docker
    pkgs-unstable.docker-compose
    pkgs.lazydocker
  ];
}
