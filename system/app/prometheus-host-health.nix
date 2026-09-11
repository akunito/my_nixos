# Host health textfile metrics — the things node_exporter cannot see
#
# node_exporter's systemd collector only lists SYSTEM units, and on the NAS the
# exporter is a rootless-docker container that sees no systemd at all. So the
# facts the Infra Alerts bot and the alert rules care most about — is the
# rootful/rootless docker daemon up, which units are failed — come from this
# oneshot instead. It writes host_health.prom into the node_exporter textfile
# directory (bind-mounted into the container on the NAS, read natively on VPS).
#
# Metrics:
#   host_docker_daemon_up{mode="rootful"|"rootless"}   1/0 per configured daemon
#   host_systemd_unit_failed{name,scope="system"|"user"} 1 per failed unit
#   host_systemd_failed_units{scope}                    count
#
# Gated by systemSettings.prometheusHostHealthEnable (default false). Which
# docker daemons are probed follows virtualisation.docker.* so the metric never
# reports a daemon the host does not run.

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  enabled = systemSettings.prometheusHostHealthEnable or false;
  rootful = config.virtualisation.docker.enable;
  rootless = config.virtualisation.docker.rootless.enable;
  # The rootless daemon and the user units live in this user's manager.
  username = userSettings.username;
  textfileDir = "/var/lib/prometheus-node-exporter/textfile";

  script = pkgs.writeShellScript "host-health-metrics" ''
    set -u
    OUT="${textfileDir}/host_health.prom"
    TMP="$OUT.tmp"
    UID_NUM=$(id -u ${username})
    # systemctl --user from root needs the target user's runtime dir + bus.
    userctl() {
      runuser -u ${username} -- env XDG_RUNTIME_DIR="/run/user/$UID_NUM" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$UID_NUM/bus" \
        systemctl --user "$@"
    }

    {
      echo "# HELP host_docker_daemon_up Docker daemon active (1) or not (0), per mode"
      echo "# TYPE host_docker_daemon_up gauge"
      ${lib.optionalString rootful ''
      if systemctl is-active --quiet docker.service; then v=1; else v=0; fi
      echo "host_docker_daemon_up{mode=\"rootful\"} $v"
      ''}
      ${lib.optionalString rootless ''
      if userctl is-active --quiet docker.service 2>/dev/null; then v=1; else v=0; fi
      echo "host_docker_daemon_up{mode=\"rootless\",user=\"${username}\"} $v"
      ''}

      echo "# HELP host_systemd_unit_failed Unit is in failed state (system or user manager)"
      echo "# TYPE host_systemd_unit_failed gauge"
      echo "# HELP host_systemd_failed_units Number of failed units per manager scope"
      echo "# TYPE host_systemd_failed_units gauge"
      n=0
      while read -r unit _; do
        [ -z "$unit" ] && continue
        echo "host_systemd_unit_failed{name=\"$unit\",scope=\"system\"} 1"
        n=$((n + 1))
      done < <(systemctl --failed --plain --no-legend 2>/dev/null)
      echo "host_systemd_failed_units{scope=\"system\"} $n"

      n=0
      while read -r unit _; do
        [ -z "$unit" ] && continue
        echo "host_systemd_unit_failed{name=\"$unit\",scope=\"user\",user=\"${username}\"} 1"
        n=$((n + 1))
      done < <(userctl --failed --plain --no-legend 2>/dev/null)
      echo "host_systemd_failed_units{scope=\"user\",user=\"${username}\"} $n"
    } > "$TMP"
    mv "$TMP" "$OUT"
    chmod 644 "$OUT"
  '';
in
lib.mkIf enabled {
  systemd.tmpfiles.rules = [ "d ${textfileDir} 0775 root wheel -" ];

  systemd.services.host-health-metrics = {
    description = "Docker daemon + failed units metrics for Prometheus textfile collector";
    after = [ "network.target" ];
    path = [ pkgs.coreutils pkgs.systemd pkgs.util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = script;
    };
  };

  systemd.timers.host-health-metrics = {
    description = "Host health metrics timer (every minute)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
    };
  };
}
