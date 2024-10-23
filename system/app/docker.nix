{ pkgs, lib, userSettings, storageDriver ? null, ... }:

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
    storageDriver = storageDriver;
    autoPrune.enable = true;
    liveRestore = true; # Fix for https://discourse.nixos.org/t/docker-hanging-on-reboot/18270/3
                        # Allow dockerd to be restarted without affecting running container.
                        # This option is incompatible with docker swarm.
  };
  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.dockerEnable == true) [ "docker" ];
  environment.systemPackages = with pkgs; lib.mkIf (userSettings.dockerEnable == true) [
    docker
    docker-compose
    lazydocker
  ];
}
