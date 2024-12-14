{ config, pkgs, systemSettings, lib, ... }:

{
  # You need to install pkgs.nfs-utils
  services.rpcbind.enable =  lib.mkIf (systemSettings.nfsClientEnable == true) true; # needed for NFS

  systemd.mounts =  lib.mkIf (systemSettings.nfsClientEnable == true) systemSettings.nfsMounts;

  systemd.automounts =  lib.mkIf (systemSettings.nfsClientEnable == true) systemSettings.nfsAutoMounts;

}
