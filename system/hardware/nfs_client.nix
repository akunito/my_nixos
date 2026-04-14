{ config, pkgs, systemSettings, lib, ... }:

{
  # You need to install pkgs.nfs-utils
  services.rpcbind.enable = lib.mkIf (systemSettings.nfsClientEnable == true) true; # needed for NFS

  systemd.mounts = lib.mkIf (systemSettings.nfsClientEnable == true)
    (map (entry: entry // {
      # Timeout mount attempts so unreachable NFS won't hang processes
      mountConfig = (entry.mountConfig or {}) // {
        TimeoutSec = "15";
      };
    }) systemSettings.nfsMounts);

  systemd.automounts = lib.mkIf (systemSettings.nfsClientEnable == true)
    (map (entry: entry // {
      # Start on boot — automount is lightweight (just a kernel trigger, no network needed)
      wantedBy = [ "multi-user.target" ];
    }) systemSettings.nfsAutoMounts);

}
