{ pkgs, pkgs-unstable, lib, userSettings, ... }:

# Rootless Docker daemon maintenance — shared by every profile that sets
# userSettings.dockerRootlessEnable (VPS_PROD, NAS_PROD). Self-gates on the flag.
#
# 1. GC-PROOF DAEMON NAMESPACE (the `lookup registry-1.docker.io on [::1]:53`
#    pull failures that used to appear "after a few weeks").
#
#    dockerd-rootless runs dockerd under rootlesskit with --copy-up=/etc: /etc
#    becomes a tmpfs, regular entries become symlinks into a hidden bind mount
#    of the real /etc (/etc/.roNNNNNNNNNN), and entries that were already
#    symlinks are copied VERBATIM. On NixOS nearly every file in /etc is
#    `X -> /etc/static/X`, and `/etc/static -> /nix/store/<gen>-etc/etc` — so the
#    daemon's namespace pins the store path of whichever generation was current
#    when it started. The next rebuild + weekly nix-gc deletes that path, and
#    from then on resolv.conf, nsswitch.conf, hosts and the CA bundle are all
#    dangling inside the daemon. Go's resolver treats a missing resolv.conf as
#    "use localhost", hence [::1]:53. Containers never notice: they get
#    daemon.settings.dns injected. Verified on VPS_PROD and NAS_PROD 2026-09-09.
#
#    dockerd-rootless.sh honours $DOCKERD for the binary it execs in the child,
#    so we point it at a wrapper that re-targets /etc/static at the live bind
#    (`.roNNN/static`, always the CURRENT generation) before exec'ing dockerd.
#    The rootlesskit child is uid 0 inside its user namespace and /etc is its
#    own tmpfs, so no privilege is involved and the real /etc is untouched.
#
# 2. docker-prune — weekly reaper for dangling images. virtualisation.docker.
#    autoPrune only wires the ROOT daemon, so the rootless side would otherwise
#    keep every image a moved tag orphans (VPS_PROD: 203 of them, ~74 GB, by
#    2026-08-18). `image prune`, NOT `system prune`: tagged rollback images,
#    volumes, networks and stopped containers are left alone, and dockerd will
#    not delete an image a container still references.
#
# 3. Reload the lingering user's systemd manager at activation. nixos-rebuild
#    only reloads the SYSTEM manager; a lingering `systemd --user` survives every
#    rebuild and never re-reads /etc/systemd/user, so any user unit added after
#    it started is silently inert (VPS_PROD's manager ran from 2026-02-21 to
#    2026-09-09 without one, and docker-prune never fired once).

let
  enabled = userSettings.dockerRootlessEnable or false;
  user = userSettings.username;
  docker = pkgs-unstable.docker;
  coreutils = "${pkgs.coreutils}/bin";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  runuser = "${pkgs.util-linux}/bin/runuser";

  # Runs INSIDE the rootlesskit child. Every guard exits 0: this must never be
  # the reason dockerd fails to start.
  fixEtcStatic = pkgs.writeShellScript "docker-rootless-fix-etc-static" ''
    # Only act in a copy-up'd /etc (tmpfs). A real /etc means we are not where
    # we think we are — leave it alone.
    [ "$(${coreutils}/stat -f -c %T /etc 2>/dev/null)" = tmpfs ] || exit 0
    [ -L /etc/static ] || exit 0
    for ro in /etc/.ro*/; do
      ro=''${ro%/}
      # The hidden bind's own /etc/static symlink always points at the current
      # generation; going through it instead of through a pinned store path is
      # the whole fix.
      if [ -d "$ro/static/" ]; then
        ${coreutils}/ln -sfn "''${ro#/etc/}/static" /etc/static
        exit 0
      fi
    done
    echo "docker-rootless: no live /etc bind found under /etc/.ro*; /etc/static left pinned" >&2
    exit 0
  '';

  dockerdChild = pkgs.writeShellScript "dockerd-rootless-child" ''
    ${fixEtcStatic}
    exec ${docker}/bin/dockerd "$@"
  '';
in
lib.mkIf enabled {
  systemd.user.services.docker = {
    environment = {
      # Let containers reach host services (databases, Redis, Postfix) through
      # the slirp4netns gateway at 10.0.2.2. rootlesskit's default is
      # --disable-host-loopback.
      DOCKERD_ROOTLESS_ROOTLESSKIT_DISABLE_HOST_LOOPBACK = "false";
      # See (1) above.
      DOCKERD = "${dockerdChild}";
    };
  };

  systemd.user.timers.docker-prune = {
    description = "Weekly rootless Docker dangling-image prune";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:00:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };
  systemd.user.services.docker-prune = {
    description = "Prune dangling (untagged) rootless Docker images";
    serviceConfig = {
      Type = "oneshot";
      # User units don't inherit the shell's DOCKER_HOST from setSocketVariable;
      # %t is XDG_RUNTIME_DIR, where the rootless daemon puts its socket.
      Environment = "DOCKER_HOST=unix://%t/docker.sock";
      ExecStart = "${docker}/bin/docker image prune -f";
    };
  };

  # (3) above. Runs after `etc` (new unit symlinks in place) and `users`. Skips
  # cleanly at boot, when no user manager is up yet. daemon-reload does NOT
  # restart running services, so the containers are untouched; the explicit
  # `start` afterwards is what actually schedules a timer that was enabled
  # while the manager wasn't looking (reload alone never starts anything).
  #
  # Talks to the user's own bus as the user (runuser + XDG_RUNTIME_DIR), not via
  # `systemctl --machine=user@.host`: that route works from an interactive root
  # shell but failed from inside nixos-rebuild's activation on VPS_PROD
  # (2026-09-09). Errors are left visible on purpose — a silent failure here is
  # exactly how docker-prune stayed inert for months.
  system.activationScripts.reloadLingeringUserManager = lib.stringAfter [ "etc" "users" ] ''
    _uid=$(${coreutils}/id -u ${user} 2>/dev/null || true)
    if [ -n "$_uid" ] && [ -S "/run/user/$_uid/bus" ]; then
      _usc="${runuser} -u ${user} -- ${coreutils}/env XDG_RUNTIME_DIR=/run/user/$_uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_uid/bus ${systemctl} --user"
      if $_usc daemon-reload; then
        for _t in /etc/systemd/user/timers.target.wants/*.timer; do
          [ -e "$_t" ] || continue
          $_usc start "$(${coreutils}/basename "$_t")" \
            || echo "docker-rootless: could not start user timer $(${coreutils}/basename "$_t")" >&2
        done
      else
        echo "docker-rootless: could not daemon-reload ${user}'s user manager (units added since it started stay inert)" >&2
      fi
    fi
    unset _uid _usc _t
  '';
}
