{ config, pkgs, systemSettings, lib, ... }:

let
  # `reap`: drop what is dead, restore what this script parked and is back.
  # `park`: before sleep — park every active trigger and unmount, unconditionally.
  # The trigger is always stopped BEFORE the lazy umount: in the other order the
  # portal re-triggered the mount in between (LAPTOP_YOGA 2026-10-01 10:32:00,
  # another 15 s hang).
  reaper = pkgs.writeShellScript "nfs-reaper" (''
    set -u
    mode=''${1:-reap}
    S=${pkgs.systemd}/bin/systemctl
    parkdir=/run/nfs-automount-parked
    park() { # $1 unit $2 where
      if [ -n "$1" ] && $S is-active -q "$1"; then
        ${pkgs.coreutils}/bin/mkdir -p "$parkdir"; : > "$parkdir/$1"
        $S stop "$1" || true
      fi
      if ${pkgs.util-linux}/bin/findmnt -t nfs,nfs4 -M "$2" >/dev/null 2>&1; then
        # -i: plain umount2(MNT_DETACH), skip the umount.nfs helper. The helper
        # talks to the server, and with the server gone it held a real suspend
        # for 2 min (LAPTOP_YOGA 2026-10-01, 11:04:33 -> 11:06:33).
        ${pkgs.util-linux}/bin/umount -l -i "$2" || true
      fi
    }
  '' + (lib.concatMapStringsSep "\n" (entry:
    let
      host = builtins.head (lib.splitString ":" entry.what);
      where = lib.escapeShellArg entry.where;
      hasAuto = builtins.any (a: a.where == entry.where) systemSettings.nfsAutoMounts;
    in ''
      unit=${if hasAuto then "$(${pkgs.systemd}/bin/systemd-escape -p --suffix=automount ${where})" else "\"\""}
      if [ "$mode" = park ]; then
        park "$unit" ${where}
      elif ${pkgs.coreutils}/bin/timeout 4 ${pkgs.bash}/bin/bash -c 'exec 3<>/dev/tcp/${host}/2049' 2>/dev/null; then
        # Up: restore only what this script parked — an automount switched off
        # by hand (sway-apps "Automount off", systemctl stop) must stay off.
        if [ -n "$unit" ] && [ -e "$parkdir/$unit" ]; then
          $S is-active -q "$unit" || { echo "${host} is back — restoring $unit"; $S start "$unit" || true; }
          ${pkgs.coreutils}/bin/rm -f "$parkdir/$unit"
        fi
      else
        # findmnt -t nfs,nfs4 rather than `mountpoint`: the autofs trigger is
        # itself a mountpoint, so `mountpoint` is true with nothing mounted.
        if { [ -n "$unit" ] && $S is-active -q "$unit"; } || ${pkgs.util-linux}/bin/findmnt -t nfs,nfs4 -M ${where} >/dev/null 2>&1; then
          echo "${host} is not answering on 2049 — parking ${entry.where}"
          park "$unit" ${where}
        fi
      fi
    '') systemSettings.nfsMounts));
in
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
        ExecStart = "${reaper} reap";
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

  # Suspend/resume. Measured on LAPTOP_YOGA 2026-10-01: it suspended at 20:09
  # with NFS_Backups MOUNTED, the NAS slept at 23:00, and on resume at 10:30
  # the dead mount sat in /mnt for 96 s until the 2-min timer caught up — the
  # portal file chooser froze inside that window. So: park everything before
  # sleeping (nothing to hang on after resume), and re-check on resume and
  # whenever NetworkManager brings a link up, so the share comes back as soon
  # as the server answers instead of up to 2 min later.
  systemd.services.nfs-park-before-sleep = lib.mkIf
    (systemSettings.nfsClientEnable == true)
    {
      description = "Unmount NFS shares and park their automount triggers before sleep";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${reaper} park";
      };
    };

  systemd.services.nfs-reap-after-resume = lib.mkIf
    (systemSettings.nfsClientEnable == true)
    {
      description = "Re-check NFS shares after resume";
      after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
      wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl start --no-block nfs-unmount-unreachable.service";
      };
    };

  networking.networkmanager.dispatcherScripts = lib.mkIf
    ((systemSettings.nfsClientEnable == true) && (systemSettings.networkManager or false))
    [{
      type = "basic";
      source = pkgs.writeShellScript "nfs-reap-dispatch" ''
        case "$2" in
          up|connectivity-change)
            ${pkgs.systemd}/bin/systemctl start --no-block nfs-unmount-unreachable.service ;;
        esac
      '';
    }];
}
