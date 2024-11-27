{ config, pkgs, systemSettings, lib, ... }:

{ 
  # NFS
  services.nfs.server = lib.mkIf (systemSettings.nfsServerEnable == true) {
    enable = true;
    exports = systemSettings.nfsExports;
    # fixed rpc.statd port; for firewall
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    extraNfsdConfig = '''';
  };
}
