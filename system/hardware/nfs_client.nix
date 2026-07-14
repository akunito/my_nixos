{ config, pkgs, systemSettings, lib, ... }:

{
  # You need to install pkgs.nfs-utils
  services.rpcbind.enable = lib.mkIf (systemSettings.nfsClientEnable == true) true; # needed for NFS

  systemd.mounts = lib.mkIf (systemSettings.nfsClientEnable == true)
    (map (entry: entry // {
      # retry=0 is load-bearing: mount.nfs otherwise retries internally for 2 minutes,
      # so TimeoutSec kills it mid-retry with SIGTERM. A SIGTERMed mount never returns an
      # error to autofs, leaving every process that touched the mountpoint stuck in
      # uninterruptible D state (autofs_wait) forever while autofs re-triggers in a loop.
      # With retry=0 the mount fails in ~3s and callers get a clean error instead.
      options = entry.options
        + (lib.optionalString (!(lib.hasInfix "retry=" entry.options)) ",retry=0");

      # Backstop in case a mount attempt still wedges (e.g. server reachable but not serving)
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
