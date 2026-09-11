# healthchecks.io dead-man's switch (AINF-368 F5)
#
# Every alert in this repo originates on the VPS (Prometheus, Alertmanager,
# infra-bot), so a dead VPS can't tell anyone. This timer pings a
# healthchecks.io check every 5 minutes; when the pings stop, healthchecks
# alerts from outside. pfSense runs the same ping from its own cron
# (created via the pfSense REST API) so "home internet down" is reported too.
#
# Flag: healthchecksPingUrl (the check's ping URL from secrets, "" = off).

{ lib, pkgs, systemSettings, ... }:

let
  url = systemSettings.healthchecksPingUrl or "";
in
lib.mkIf (url != "") {
  systemd.services.healthchecks-ping = {
    description = "Ping healthchecks.io (dead-man's switch)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      ExecStart = "${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 -o /dev/null ${url}";
    };
  };

  systemd.timers.healthchecks-ping = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      AccuracySec = "30s";
    };
  };
}
