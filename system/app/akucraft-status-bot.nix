# AkuCraft Telegram bot (announcements + group commands)
#
# Persistent daemon (system/app/akucraft-bot.py) that:
#   - announces server ONLINE/OFFLINE, player joins/leaves, deaths, advancements
#   - auto-stops servers left empty (45 min) and lets the group /start them again
#   - serves group commands: /start /stop /status /players /connect /vpn /help
#
# The Minecraft stack is rootless docker under user akunito (~/.homelab/minecraft*),
# so the service runs as that user against /run/user/1000/docker.sock (lingering
# is enabled on VPS_PROD, so the socket exists without an active session).
#
# NOTE: docker/docker-compose MUST come from pkgs-unstable — pkgs.docker (28.x)
# is marked insecure on the pinned stable nixpkgs and refuses to evaluate.
# Same pin rule as everywhere else in this repo (see docker EOL notes).
#
# Gated by systemSettings.akucraftStatusBotEnable + non-empty telegram secrets:
#   secrets/domains.nix: akucraftTelegramBotToken, akucraftTelegramChatId
#
# State (announce dedup, telegram offset) lives in /var/lib/akucraft-status.

{ config, lib, pkgs, pkgs-unstable, systemSettings, ... }:

let
  secrets = import ../../secrets/domains.nix;
  token = secrets.akucraftTelegramBotToken or "";
  chatId = secrets.akucraftTelegramChatId or "";
  enabled = (systemSettings.akucraftStatusBotEnable or false) && token != "" && chatId != "";
  # The rootless docker socket (uid 1000) and ~/.homelab both belong to this
  # user, and the service already runs as them.
  username = "akunito";

  # Discord is optional and split in two independent halves:
  #   webhook  -> announcements only (no bot account, no dependency)
  #   bot token + guild -> slash commands over the gateway (needs discord.py)
  discordWebhook = secrets.akucraftDiscordWebhookUrl or "";
  discordToken = secrets.akucraftDiscordBotToken or "";
  discordGuild = secrets.akucraftDiscordGuildId or "";
  discordChannel = secrets.akucraftDiscordChannelId or "";
  discordCommands = discordToken != "" && discordGuild != "";

  # Auto-role on join: the bot matches the new member against the invite codes
  # of our own invite links, so joins through other invites are left alone.
  discordJoinRoles = secrets.akucraftDiscordJoinRoleIds or "";
  # Invite codes are the last path segment of the discord.gg links in secrets.
  inviteCode = link: lib.last (lib.splitString "/" link);
  discordInviteCodes = lib.concatStringsSep "," (map inviteCode
    (lib.filter (l: l != "") [
      (secrets.akucraftDiscordInviteChat or "")
      (secrets.akucraftDiscordInviteVoice or "")
    ]));

  python = if discordCommands
    then pkgs.python3.withPackages (ps: [ ps.discordpy ])
    else pkgs.python3;
in
lib.mkIf enabled {
  systemd.services.akucraft-status-bot = {
    description = "AkuCraft Telegram bot (status + commands)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      TG_TOKEN = token;
      TG_CHAT = chatId;
      DISCORD_WEBHOOK = discordWebhook;
      DISCORD_TOKEN = discordToken;
      DISCORD_GUILD = discordGuild;
      DISCORD_CHANNEL = discordChannel;
      DISCORD_JOIN_ROLES = discordJoinRoles;
      DISCORD_INVITE_CODES = discordInviteCodes;
      DOCKER_HOST = "unix:///run/user/1000/docker.sock";
      IDLE_STOP_MINUTES = "45";
      # /invite - players onboard their own friends instead of Diego doing it
      # over SSH. Empty string disables the command entirely.
      INVITE_SCRIPT = "/home/${username}/.homelab/minecraft/akucraft-invite.sh";
      INVITE_ROLES = "MCplayer,MCadmin";
      # akucraft-invite.sh (driven by /invite) additionally needs bash, python3,
      # sudo and sendmail. /run/wrappers/bin carries the setuid sudo and the
      # sendmail wrapper; without them the invite dies with "command not found"
      # rather than anything that looks like a permissions problem.
      PATH = lib.mkForce (lib.makeBinPath [
        pkgs-unstable.docker
        pkgs-unstable.docker-compose
        pkgs.coreutils
        pkgs.bash
        pkgs.python3
        pkgs.gnugrep
        pkgs.gnused
      ] + ":/run/wrappers/bin:/run/current-system/sw/bin");
    };
    serviceConfig = {
      Type = "simple";
      User = username;
      ExecStart = "${python}/bin/python3 ${./akucraft-bot.py}";
      Restart = "always";
      RestartSec = 10;
      StateDirectory = "akucraft-status";
    };
    unitConfig = {
      # Restart=always covers crashes, but a unit that gives up entirely would
      # otherwise go unnoticed - the bot is how everyone sees server state, so
      # its own silence must page us. OnFailure must live in [Unit].
      OnFailure = lib.optional (systemSettings.notificationOnFailureEnable or false)
        "notify-failure@%n.service";
    };
  };

  # /invite calls akucraft-invite.sh, which needs headscale - a root-only
  # binary. Grant exactly the two subcommands it uses rather than blanket
  # sudo or the whole binary. Every key it can mint is still tag:mc-guest,
  # so the ACL keeps the guest to the game port and the map and nothing else.
  security.sudo.extraRules = [{
    users = [ username ];
    commands = [
      { command = "/run/current-system/sw/bin/headscale users create *";       options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/headscale preauthkeys create *"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
