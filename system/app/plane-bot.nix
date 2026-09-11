# Plane Telegram bot (@aku_plane_bot) — runs next to Plane on VPS_PROD
#
# Daemon: system/app/plane-bot/plane_bot.py (+ system/app/tgcommon.py, shared
# with the other Telegram bots). One forum group per audience; the chat ->
# projects table (planeBotChats) is the ONLY scope: a chat can list, create
# in and hear about the projects in its row and nothing else. Every write to
# Plane uses the API token of the person who typed the command (planeBotUsers),
# so Plane's own permissions apply on top.
#
# The bot keeps a sqlite mirror of the in-scope projects (the v1 list API has
# no filters), synced with planeBotSyncAlias's token every planeBotPollSeconds.
#
# The package runs the unit tests (tests/) in checkPhase: a scope regression
# fails the build, so install.sh never deploys it.
#
# Gated by systemSettings.planeBotEnable + planeBotToken + planeBotChats.
# CLI on the host: `plane-bot sync`, `plane-bot simulate --chat ID [--thread N]
# [--user TGID] "/status all"` (needs the env: see the unit).

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  token = systemSettings.planeBotToken or "";
  chats = systemSettings.planeBotChats or { };
  users = systemSettings.planeBotUsers or { };
  enabled = (systemSettings.planeBotEnable or false) && token != "" && chats != { };
  username = userSettings.username;

  pkg = pkgs.callPackage ./plane-bot/package.nix { };
in
lib.mkIf enabled {
  # Tokens (bot + one Plane API token per person) never go into the unit's
  # Environment= (visible in `systemctl show`); they ride in a root-only file.
  environment.etc."secrets/plane-bot.env" = {
    text = ''
      TELEGRAM_BOT_TOKEN=${token}
      PLANE_USERS=${builtins.toJSON users}
    '';
    mode = "0400";
    user = "root";
  };

  environment.systemPackages = [ pkg ];

  systemd.services.plane-bot = {
    description = "Plane Telegram bot (commands + mirror sync)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      PLANE_CHATS = builtins.toJSON chats;
      PLANE_URL = systemSettings.planeApiUrl or "";
      PLANE_PUBLIC_URL = systemSettings.planeBotPublicUrl or (systemSettings.planeApiUrl or "");
      PLANE_WORKSPACE = systemSettings.planeWorkspaceSlug or "";
      SYNC_ALIAS = systemSettings.planeBotSyncAlias or "";
      ACTIVE_STATES = systemSettings.planeBotActiveStates or "In Progress,In Review,Todo";
      POLL_SECONDS = toString (systemSettings.planeBotPollSeconds or 60);
      FULL_SYNC_MINUTES = toString (systemSettings.planeBotFullSyncMinutes or 60);
      STATE_DIR = "/var/lib/plane-bot";
      TZ = systemSettings.timezone or "Europe/Warsaw";
      PYTHONUNBUFFERED = "1";
    };
    serviceConfig = {
      User = username;
      EnvironmentFile = "/etc/secrets/plane-bot.env";
      ExecStart = "${pkg}/bin/plane-bot";
      Restart = "always";
      RestartSec = 10;
      StateDirectory = "plane-bot";
    };
  };
}
