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

  # ---------------------------------------------------------------------------
  # Stale-mount reaper
  #
  # retry=0 above fixes MOUNTING while the server is asleep. It does nothing for
  # the opposite order: a share mounted while the NAS was awake, which then goes
  # stale when the NAS sleeps (it does, 23:00-16:00). Every process that so much
  # as stats the mountpoint then blocks in `rpc_wait_bit_killable` for as long as
  # `timeo`/`retrans` allow. On LAPTOP_A that froze Gwenview hard enough for KWin
  # to offer to kill it, and inflated the load average with D-state tasks while
  # the CPU sat idle.
  #
  # TimeoutIdleSec cannot save you here: the expiry umount returns EBUSY
  # ("umount.nfs4: /mnt/NFS_Backups: device is busy", status=16), so systemd
  # gives up and the mount survives. LAPTOP_A's had been up for seven days.
  #
  # A LAZY umount detaches the tree without talking to the dead server and works
  # where the normal one fails. Afterwards the automount trigger is still in
  # place, so the next access re-mounts if the NAS is back — and if it is not,
  # retry=0 makes that attempt fail in ~3s instead of blocking.
  #
  # Unconditional for every NFS client: it is a safety net, not a feature. The
  # check is one 4s TCP probe per mount every 5 min, so it is free where the
  # server is always up, and load-bearing where it sleeps. (Now every 2 min, and
  # it also removes/restores the autofs trigger itself — see the script.) Making it opt-in was
  # itself the bug — DESK and DESK_A both mount the sleeping NAS and neither had
  # opted in, so a plain file delete in Dolphin hung forever (kio_trash scans
  # every mountpoint for .Trash-$uid).
  # ---------------------------------------------------------------------------
  systemd.services.nfs-unmount-unreachable = lib.mkIf
    (systemSettings.nfsClientEnable == true)
    {
      description = "Drop NFS mounts and automount triggers whose server has gone away";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "nfs-unmount-unreachable" (''
          set -u
        '' + (lib.concatMapStringsSep "\n" (entry:
          let host = builtins.head (lib.splitString ":" entry.what);
          in ''
            # findmnt -t nfs,nfs4 rather than `mountpoint`: the autofs trigger is
            # itself a mountpoint, so `mountpoint` is true even with nothing
            # mounted, and we would unmount the trigger instead of the share.
            if ${pkgs.coreutils}/bin/timeout 4 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/${host}/2049' 2>/dev/null; then
              up=1
            else
              up=0
            fi
            if [ "$up" = 0 ] && ${pkgs.util-linux}/bin/findmnt -t nfs,nfs4 -M ${lib.escapeShellArg entry.where} >/dev/null 2>&1; then
              echo "${host} is not answering on 2049 — lazily unmounting ${entry.where}"
              ${pkgs.util-linux}/bin/umount -f -l ${lib.escapeShellArg entry.where} || true
            fi
          '' + lib.optionalString (builtins.any (a: a.where == entry.where) systemSettings.nfsAutoMounts) ''
            # The autofs trigger only exists while the server answers. "retry=0
            # fails in ~3s" holds on the LAN (ICMP unreachable); a sleeping
            # TAILNET peer drops packets silently, so each attempt burns the full
            # TimeoutSec=15 — and the KDE portal file chooser statfs()es every
            # mount in mountinfo and retries. Measured on LAPTOP_YOGA 2026-09-30:
            # 11 requests for a dead share from xdg-desktop-portal-kde, VS Code's
            # "Open Folder" frozen, the portal dumped core; reproduced with a
            # probe automount (4 requests in 22 s, nobody navigating).
            unit=$(${pkgs.systemd}/bin/systemd-escape -p --suffix=automount ${lib.escapeShellArg entry.where})
            # Only restore what THIS service parked: an automount switched off by
            # hand (sway-apps "Automount off", systemctl stop) must stay off.
            parked=/run/nfs-automount-parked/$unit
            if [ "$up" = 1 ]; then
              if [ -e "$parked" ]; then
                if ! ${pkgs.systemd}/bin/systemctl is-active -q "$unit"; then
                  echo "${host} is back — restoring $unit"
                  ${pkgs.systemd}/bin/systemctl start "$unit" || true
                fi
                ${pkgs.coreutils}/bin/rm -f "$parked"
              fi
            else
              if ${pkgs.systemd}/bin/systemctl is-active -q "$unit"; then
                echo "${host} is not answering on 2049 — removing $unit"
                ${pkgs.coreutils}/bin/mkdir -p /run/nfs-automount-parked
                : > "$parked"
                ${pkgs.systemd}/bin/systemctl stop "$unit" || true
              fi
            fi
          '') systemSettings.nfsMounts));
      };
    };

  systemd.timers.nfs-unmount-unreachable = lib.mkIf
    (systemSettings.nfsClientEnable == true)
    {
      description = "Check for stale NFS mounts every few minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "20s";
        OnUnitActiveSec = "2min";
        AccuracySec = "15s";
      };
    };

}
