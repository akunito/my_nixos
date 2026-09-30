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
  port = toString (systemSettings.unfs3Port or 2049);
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
      # -l 0.0.0.0: WSL's localhost relay only tracks IPv4 listeners (same
      #     trap as harmonia, see DESK_W11-config.nix).
      ExecStart = "${pkgs.unfs3}/bin/unfsd -d -s -p -t -n ${port} -m ${port} -l 0.0.0.0 -e ${exportsFile}";
      User = userSettings.username;
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  networking.firewall.interfaces = lib.genAttrs (systemSettings.unfs3Interfaces or [ ]) (_: {
    allowedTCPPorts = [ (systemSettings.unfs3Port or 2049) ];
  });
}
