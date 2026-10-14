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
      # "ip" only covers the default bridge. Compose creates its own networks, and
      # there `ports:` bound 0.0.0.0 AND [::] — leftyworkout's Vite 3111 was open to
      # the whole tailnet (measured 2026-10-14 from NAS_PROD). The bridge option
      # below is applied to every network created afterwards (existing networks
      # keep their options: recreate them); with it only 127.0.0.1 is bound, no [::].
      "default-network-opts" = {
        bridge = { "com.docker.network.bridge.host_binding_ipv4" = "127.0.0.1"; };
      };
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
  # and starts timers. Two gaps, both measured on DESK 2026-10-14:
  # - docker.service is wantedBy default.target, so on the first deploy nothing
  #   starts it and `docker` fails until the next login → start it.
  # - nixos-rebuild never restarts USER units: after a daemon.json change the
  #   running rootless dockerd kept the old --config-file (the default-network-opts
  #   port fix did not apply until a manual restart). Restart it when the running
  #   config differs from the unit's — but only with no running containers (rootless
  #   has no live-restore); otherwise say so and leave the restart to the user.
  system.activationScripts.startRootlessDockerWorkstation = lib.stringAfter [ "etc" "users" "reloadLingeringUserManager" ] ''
    _uid=$(${coreutils}/id -u ${user} 2>/dev/null || true)
    if [ -n "$_uid" ] && [ -S "/run/user/$_uid/bus" ]; then
      _usc="${runuser} -u ${user} -- ${coreutils}/env XDG_RUNTIME_DIR=/run/user/$_uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$_uid/bus ${systemctl} --user"
      _want=$($_usc show docker.service -p ExecStart 2>/dev/null | ${pkgs.gnugrep}/bin/grep -o -- '--config-file=[^ ;]*' | ${coreutils}/head -1)
      _pid=$(${pkgs.procps}/bin/pgrep -u "$_uid" -x dockerd | ${coreutils}/head -1)
      _have=""
      [ -n "$_pid" ] && _have=$(${coreutils}/tr '\0' '\n' < /proc/$_pid/cmdline | ${pkgs.gnugrep}/bin/grep -- '^--config-file=' | ${coreutils}/head -1)
      if [ -z "$_pid" ]; then
        $_usc start docker.service || echo "docker-rootless: could not start ${user}'s docker.service" >&2
      elif [ -n "$_want" ] && [ "$_want" != "$_have" ]; then
        _running=$(${runuser} -u ${user} -- ${coreutils}/env DOCKER_HOST=unix:///run/user/$_uid/docker.sock ${pkgs-unstable.docker}/bin/docker ps -q 2>/dev/null | ${coreutils}/wc -l)
        if [ "$_running" = 0 ]; then
          $_usc restart docker.service && echo "docker-rootless: daemon config changed, restarted ${user}'s docker.service" >&2
        else
          echo "docker-rootless: daemon config changed but $_running rootless container(s) are running; run 'systemctl --user restart docker' when convenient (until then the old config stays in effect)" >&2
        fi
      fi
    fi
    unset _uid _usc _want _pid _have _running
  '';
}
