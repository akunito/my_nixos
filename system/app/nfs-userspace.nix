# Userspace NFSv3 server (unfs3) — for paths the kernel server cannot export.
#
# Exists for DESK_W11: the DESK Games drives are NTFS volumes Windows has
# mounted (D:, E:), so WSL only sees them through 9p/drvfs, and knfsd refuses
# those — measured 2026-09-30: name_to_handle_at("/mnt/d/Games") = ENOTSUP,
# while /home (ext4) returns a handle. unfs3 builds its handles from dev+inode
# in userspace, so it serves them: 162 MB/s sequential read over a local v3
# mount, byte-identical to the direct read.
#
# NFSv3 only, fixed port for both NFS and MOUNT, TCP only, no portmapper —
# clients need `vers=3,tcp,port=N,mountport=N,nolock`.
#
# Behind WSL NAT every client arrives from the Windows portproxy, so the
# export list cannot tell peers apart: access control is the Windows firewall
# rule + the portproxy's listen address. Hence read-only by default.
{ lib, pkgs, systemSettings, userSettings, ... }:

let
  exports = systemSettings.unfs3Exports or [ ];
  publicPort = systemSettings.unfs3Port or 2049;
  # unfsd only opens AF_INET6 sockets (v4-mapped, "[::ffff:0.0.0.0]:2049" in ss
  # even with -l 0.0.0.0), and WSL's localhost relay forwards AF_INET listeners
  # only — measured 2026-09-30: Windows -> 127.0.0.1:2049 refused while
  # 127.0.0.1:5000 (harmonia, AF_INET) and <eth0 ip>:2049 both answered. With
  # unfs3Ipv4Proxy a systemd socket owns the real IPv4 port and proxies to
  # unfsd on loopback.
  ipv4Proxy = systemSettings.unfs3Ipv4Proxy or false;
  backendPort = if ipv4Proxy then publicPort + 10000 else publicPort;
  port = toString backendPort;
  bind = if ipv4Proxy then "127.0.0.1" else "0.0.0.0";
  mode = if (systemSettings.unfs3ReadOnly or true) then "ro" else "rw";
  exportsFile = pkgs.writeText "unfs3-exports" (
    lib.concatMapStrings (p: "${p} 0.0.0.0/0(${mode},insecure)\n") exports
  );
in
lib.mkIf ((systemSettings.unfs3Enable or false) && exports != [ ]) {
  systemd.services.unfs3 = {
    description = "Userspace NFSv3 server (unfs3)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      # -s: single-user mode, every request runs as this user (no root needed,
      #     and drvfs maps everything to it anyway).
      ExecStart = "${pkgs.unfs3}/bin/unfsd -d -s -p -t -n ${port} -m ${port} -l ${bind} -e ${exportsFile}";
      User = userSettings.username;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.sockets.unfs3-proxy = lib.mkIf ipv4Proxy {
    description = "IPv4 listener for unfs3";
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "0.0.0.0:${toString publicPort}" ];
  };
  systemd.services.unfs3-proxy = lib.mkIf ipv4Proxy {
    description = "IPv4 proxy to unfs3";
    requires = [ "unfs3.service" "unfs3-proxy.socket" ];
    after = [ "unfs3.service" "unfs3-proxy.socket" ];
    serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${port}";
  };

  networking.firewall.interfaces = lib.genAttrs (systemSettings.unfs3Interfaces or [ ]) (_: {
    allowedTCPPorts = [ (systemSettings.unfs3Port or 2049) ];
  });
}
