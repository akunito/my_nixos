# Alertmanager — the piece that was missing between Prometheus and Telegram
#
# Every alert rule in this repo is a PROMETHEUS rule (grafana.nix ruleFiles,
# prometheus-blackbox.nix). Prometheus only evaluates them; delivering them is
# Alertmanager's job, and until 2026-09-11 none was configured, so the 40+
# rules fired into the void (47 active when this was written). Grafana's own
# contact points never applied: they only serve Grafana-managed rules, of
# which there are none.
#
# Routing (AINF-368):
#   critical  -> Telegram "Infra Alerts" 🚨 Alerts topic, ONCE per problem
#                (repeat_interval 7d) + a 🟢 resolved message; also email
#   warning   -> email only; the Sunday digest in 📋 Weekly is the bot's job
#   node=nas  -> muted 23:00-16:05 Europe/Warsaw (the NAS sleeps on a timer)
#   HostDown  -> inhibits every other alert of the same node
#
# The bot token reaches the DynamicUser'd service through the NixOS module's
# environmentFile + envsubst: the config says $TELEGRAM_BOT_TOKEN, systemd
# reads the root-only env file. Grafana gets an Alertmanager datasource so the
# Alerting UI shows these alerts and silences can be made there.

{ config, lib, pkgs, systemSettings, ... }:

let
  enabled = systemSettings.grafanaEnable or false;
  telegramBotToken = systemSettings.grafanaTelegramBotToken or "";
  telegramChatId = systemSettings.grafanaTelegramChatId or "";
  alertsThreadId = systemSettings.infraTelegramAlertsThreadId or "";
  telegramEnabled = telegramBotToken != "" && telegramChatId != "";

  alertEmail = systemSettings.notificationToEmail or "";
  alertsFrom = systemSettings.grafanaAlertsFrom or systemSettings.notificationFromEmail or "alerts@example.com";
  smtpHost = systemSettings.smtpRelayHost or "127.0.0.1:25";
  emailEnabled = alertEmail != "";
  timezone = systemSettings.timezone or "Europe/Warsaw";

  # Telegram HTML. Leds: 🔴 critical, 🟡 warning, 🟢 resolved. Everything that
  # came from an annotation is escaped — parse_mode=HTML rejects a bare "<".
  # No "$" anywhere in here: the config file goes through envsubst.
  telegramTemplate = pkgs.writeText "infra-alerts.tmpl" ''
    {{ define "infra.esc" }}{{ . | reReplaceAll "&" "&amp;" | reReplaceAll "<" "&lt;" | reReplaceAll ">" "&gt;" }}{{ end }}
    {{ define "infra.led" }}{{ if eq .Status "firing" }}{{ if eq .Labels.severity "critical" }}🔴{{ else }}🟡{{ end }}{{ else }}🟢{{ end }}{{ end }}
    {{ define "infra.where" }}{{ with .Labels.node }}{{ . }}{{ else }}{{ .Labels.instance }}{{ end }}{{ end }}
    {{ define "infra.telegram" }}{{ range .Alerts }}{{ template "infra.led" . }} <b>{{ if eq .Status "firing" }}{{ .Labels.severity | toUpper }}{{ else }}RESOLVED{{ end }}</b> · <b>{{ template "infra.where" . }}</b> · {{ .Labels.alertname }}
    {{ template "infra.esc" .Annotations.summary }}{{ if and (eq .Status "firing") .Annotations.description }}
    <i>{{ template "infra.esc" .Annotations.description }}</i>{{ end }}
    {{ end }}{{ end }}
  '';

  emailConfig = {
    to = alertEmail;
    from = alertsFrom;
    smarthost = smtpHost;
    require_tls = false;
    send_resolved = false;
  };

  telegramConfig = {
    bot_token = "$TELEGRAM_BOT_TOKEN";
    chat_id = lib.toInt telegramChatId;
    parse_mode = "HTML";
    message = ''{{ template "infra.telegram" . }}'';
    send_resolved = true;
  } // lib.optionalAttrs (alertsThreadId != "") {
    message_thread_id = lib.toInt alertsThreadId;
  };

  nasMute = {
    receiver = "warnings";
    matchers = [ ''node="nas"'' ];
    mute_time_intervals = [ "nas_sleep" ];
    routes = [{
      receiver = "critical";
      matchers = [ ''severity="critical"'' ];
      mute_time_intervals = [ "nas_sleep" ];
    }];
  };
in
lib.mkIf enabled {
  environment.etc."secrets/alertmanager.env" = lib.mkIf telegramEnabled {
    text = "TELEGRAM_BOT_TOKEN=${telegramBotToken}\n";
    mode = "0400";
    user = "root";
  };

  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9093;
    environmentFile = lib.mkIf telegramEnabled "/etc/secrets/alertmanager.env";
    # Must exceed repeat_interval (168h) or Alertmanager forgets it already
    # notified and re-sends after the default 120h.
    # log.level=debug is temporary (AINF-368 test cycle): it prints mute/notify decisions.
    extraFlags = [ "--data.retention=240h" "--log.level=debug" ];
    configuration = {
      global.resolve_timeout = "5m";
      templates = [ "${telegramTemplate}" ];

      time_intervals = [{
        name = "nas_sleep";
        time_intervals = [
          { times = [{ start_time = "23:00"; end_time = "24:00"; }]; location = timezone; }
          # rtcwake fires at 16:00; give the exporters and the "for" windows a few minutes
          { times = [{ start_time = "00:00"; end_time = "16:05"; }]; location = timezone; }
        ];
      }];

      route = {
        receiver = "warnings";
        group_by = [ "alertname" "node" ];
        group_wait = "30s";
        group_interval = "5m";
        # "Once per problem": a still-firing alert is not re-announced for a week.
        repeat_interval = "168h";
        routes = [
          nasMute
          { receiver = "critical"; matchers = [ ''severity="critical"'' ]; }
        ];
      };

      # A node that is down does not need 20 follow-up alerts about its services.
      inhibit_rules = [{
        source_matchers = [ ''alertname="HostDown"'' ];
        target_matchers = [ ''alertname!="HostDown"'' ];
        equal = [ "node" ];
      }];

      receivers = [
        {
          name = "warnings";
          email_configs = lib.optionals emailEnabled [ emailConfig ];
        }
        {
          name = "critical";
          email_configs = lib.optionals emailEnabled [ emailConfig ];
          telegram_configs = lib.optionals telegramEnabled [ telegramConfig ];
        }
      ];
    };
  };

  # Point Prometheus at it — this line is what turns rules into notifications.
  services.prometheus.alertmanagers = [{
    scheme = "http";
    static_configs = [{ targets = [ "127.0.0.1:9093" ]; }];
  }];

  # Show it in Grafana's Alerting UI (silences, active alerts) without moving
  # any rule into Grafana.
  services.grafana.provision.datasources.settings.datasources = [{
    name = "Alertmanager";
    type = "alertmanager";
    uid = "alertmanager";
    url = "http://127.0.0.1:9093";
    editable = false;
    jsonData = {
      implementation = "prometheus";
      handleGrafanaManagedAlerts = false;
    };
  }];
}
