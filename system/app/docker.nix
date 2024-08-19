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
  };
  users.users.${userSettings.username}.extraGroups = lib.mkIf (userSettings.dockerEnable == true) [ "docker" ];
  environment.systemPackages = with pkgs; lib.mkIf (userSettings.dockerEnable == true) [
    docker
    docker-compose
    lazydocker
  ];
}
