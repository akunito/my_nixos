# Infra Alerts Telegram bot (AINF-368) — runs on the monitoring server (VPS_PROD)
#
# Daemon: system/app/infra-bot.py. Read-only except /restart (F4). It serves:
#   - a relay on the Tailscale interface (POST /deploy, GET /alerts?node=)
#     that lets secrets-free nodes announce deploys and any node ask for its
#     active alerts without holding the bot token; identity = source
#     Tailscale IP resolved with `tailscale status`
#   - group commands /status [node [full]] /alerts /deploys /help, answered in
#     the topic they were asked in, and the Sunday 10:00 digest into 📋 Weekly
#   - /restart <node> docker-rootless|docker-rootful: admins only
#     (infraTelegramAdminUserIds), inline confirm button, runs `sudo -n
#     infra-restart` locally or over BatchMode ssh (infraRestartSshTargets)
#
# Gated by systemSettings.infraBotEnable + non-empty grafanaTelegramBotToken /
# grafanaTelegramChatId (the same bot Alertmanager and notify-failure use).
# Runs as the primary user like the AkuCraft bot: F4 (/restart of rootless
# docker) needs that user's socket, and `tailscale status` works unprivileged.

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  token = systemSettings.grafanaTelegramBotToken or "";
  chatId = systemSettings.grafanaTelegramChatId or "";
  enabled = (systemSettings.infraBotEnable or false) && token != "" && chatId != "";
  port = systemSettings.infraBotPort or 8765;
  username = userSettings.username;

  # tailscale hostname -> Prometheus node label, from the scrape target list
  # (hosts given as IPs never relay: they hold the token and post directly)
  nodeMap = builtins.listToAttrs (map (t: { name = t.host; value = t.name; })
    (systemSettings.prometheusRemoteTargets or []));

  python = pkgs.python3;
  bot = pkgs.writeScriptBin "infra-bot" ''
    #!${python}/bin/python3
    ${builtins.readFile ./infra-bot.py}
  '';
in
lib.mkIf enabled {
  environment.etc."secrets/infra-bot.env" = {
    text = ''
      TELEGRAM_BOT_TOKEN=${token}
      TELEGRAM_CHAT_ID=${chatId}
    '';
    mode = "0400";
    user = "root";
  };

  systemd.services.infra-bot = {
    description = "Infra Alerts Telegram bot (relay + commands)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" "alertmanager.service" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.tailscale pkgs.coreutils pkgs.openssh "/run/wrappers" ]; # ssh for remote /restart, sudo wrapper for the local one
    environment = {
      THREAD_DEPLOYS = systemSettings.infraTelegramDeploysThreadId or "";
      THREAD_ALERTS = systemSettings.infraTelegramAlertsThreadId or "";
      THREAD_WEEKLY = systemSettings.infraTelegramWeeklyThreadId or "";
      LISTEN_PORT = toString port;
      ALERTMANAGER_URL = "http://127.0.0.1:${toString config.services.prometheus.alertmanager.port}";
      PROMETHEUS_URL = "http://127.0.0.1:${toString config.services.prometheus.port}";
      NODE_MAP = builtins.toJSON nodeMap;
      ADMIN_USER_IDS = systemSettings.infraTelegramAdminUserIds or "";
      RESTART_SSH_TARGETS = builtins.toJSON (systemSettings.infraRestartSshTargets or {});
      LOCAL_NODE = systemSettings.infraNodeName or "vps";
      STATE_DIR = "/var/lib/infra-bot";
      TZ = systemSettings.timezone or "Europe/Warsaw";
      SLEEP_NODE = "nas";
      SLEEP_WINDOW = "23:00-16:05"; # keep in step with alertmanager.nix nas_sleep
      DIGEST_WEEKDAY = "6"; # Sunday
      DIGEST_HOUR = "10";
      PYTHONUNBUFFERED = "1";
    };
    serviceConfig = {
      User = username;
      EnvironmentFile = "/etc/secrets/infra-bot.env";
      ExecStart = "${bot}/bin/infra-bot";
      Restart = "always";
      RestartSec = 10;
      StateDirectory = "infra-bot";
    };
  };

  # Reachable from the tailnet only; never on the public interface.
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ port ];
}
