{ config, pkgs, systemSettings, lib, ... }:

{
  # You need to install pkgs.nfs-utils
  services.rpcbind.enable = true; # needed for NFS
  systemd.mounts = let commonMountOptions = {
    type = "nfs";
    mountConfig = {
      Options = "noatime";
    };
  };

  in

  [
    (commonMountOptions // {
      what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Books";
      where = "/mnt/NFS_Books";
    })

    (commonMountOptions // {
      what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Movies";
      where = "/mnt/NFS_Movies";
    })

    (commonMountOptions // {
      what = "192.168.8.80:/mnt/DATA_4TB/Warehouse/Media";
      where = "/mnt/NFS_Media";
    })
  ];

  systemd.automounts = let commonAutoMountOptions = {
    wantedBy = [ "multi-user.target" ];
    automountConfig = {
      TimeoutIdleSec = "600";
    };
  };

  in

  [
    (commonAutoMountOptions // { where = "/mnt/NFS_Books"; })
    (commonAutoMountOptions // { where = "/mnt/NFS_Movies"; })
    (commonAutoMountOptions // { where = "/mnt/NFS_Media"; })
  ];
}
