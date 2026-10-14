{ pkgs, pkgs-unstable, lib, userSettings, systemSettings, ... }:
# Rootless Docker as the default daemon on workstations (DESK, LAPTOP_X13) —
# AINF-407, plan docs/akunito/plans/docker-rootless-workstations.md.
# Hybrid like NAS_PROD: the root daemon from docker.nix stays for a closed list of
# exceptions (host packet capture, NET_ADMIN, undelegable devices) and, with
# dockerRootRequiresSudo, is reachable only through sudo.
# VPS/NAS keep their own rootless blocks (profiles/vps/base.nix,
# profiles/homelab/base.nix); this module is not imported there.
let
  enabled = userSettings.dockerRootlessEnable or false;
  user = userSettings.username;
  coreutils = "${pkgs.coreutils}/bin";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  runuser = "${pkgs.util-linux}/bin/runuser";
in
lib.mkIf enabled {
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
    package = pkgs-unstable.docker;
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = { "max-size" = "10m"; "max-file" = "3"; };
      # `-p 5432:5432` publishes on loopback only. rootlesskit binds on the host,
      # where tailscale0 is accepted by ts-input before nixos-fw and the DOCKER-USER
      # backstop (docker-firewall.nix) never sees rootless NAT — 0.0.0.0 would reach
      # every tailnet peer. Ports that must be reachable are published explicitly
      # on the machine's tailscale IP in the compose file.
      "ip" = "127.0.0.1";
      # No "dns": DESK/X13 run without resolved and /etc/resolv.conf points at
      # pfSense, which slirp reaches; forcing public DNS loses split-horizon.
    }
    // lib.optionalAttrs (systemSettings.dockerRootlessKrunEnable or false) {
      # crun built +LIBKRUN: each container gets its own KVM microVM with its own
      # kernel (libkrunfw). Opt-in per container with `--runtime krun`.
      "runtimes" = { krun = { path = "${pkgs-unstable.crun}/bin/krun"; }; }; # unstable: stable ships crun 1.24, without the 2026 libkrun CVE fixes
    }
    // (import ../../lib/docker-buildkit-gc.nix { });
  };

  # Dev stacks keep running after logout.
  users.users.${user}.linger = true;

  # The maintenance module's activation hook only daemon-reloads the user manager
  # and starts timers; docker.service is wantedBy default.target, so on the first
  # deploy nothing starts it and `docker` fails until the next login. Start it
  # here (no-op when already running).
  system.activationScripts.startRootlessDockerWorkstation = lib.stringAfter [ "etc" "users" "reloadLingeringUserManager" ] ''
    _uid=$(${coreutils}/id -u ${user} 2>/dev/null || true)
    if [ -n "$_uid" ] && [ -S "/run/user/$_uid/bus" ]; then
      ${runuser} -u ${user} -- ${coreutils}/env XDG_RUNTIME_DIR=/run/user/$_uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_uid/bus ${systemctl} --user start docker.service \
        || echo "docker-rootless: could not start ${user}'s docker.service" >&2
    fi
    unset _uid
  '';
}
