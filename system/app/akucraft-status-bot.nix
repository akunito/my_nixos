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

  # /ask needs the gateway reachable AND its bearer token. Both come from the
  # LiteLLM settings so there is one source of truth for the endpoint.
  askToken = secrets.litellmMasterKey or "";
  litellmHost = systemSettings.litellmHost or "127.0.0.1";
  litellmPort = systemSettings.litellmPort or 4711;
  askEnable = (systemSettings.akucraftAskEnable or false) && askToken != "";

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
      IDLE_STOP_MINUTES = toString (systemSettings.akucraftIdleStopMinutes or 45);
      # Non-empty = the server may not be stopped, by the idle timer or by
      # anyone's /stop. The text is what players are told when they try.
      STOP_LOCK_REASON = systemSettings.akucraftStopLockReason or "";
      # Test accounts whose activity is never announced anywhere - joins,
      # leaves, deaths and advancements are all suppressed. Death lines name
      # the killer too, so without this a tester dying to a boss under
      # development publishes its name to everyone.
      HIDDEN_PLAYERS = lib.concatStringsSep "," (systemSettings.akucraftHiddenPlayers or [ ]);
      # /invite - players onboard their own friends instead of Diego doing it
      # over SSH. Empty string disables the command entirely.
      INVITE_SCRIPT = "/home/${username}/.homelab/minecraft/akucraft-invite.sh";
      INVITE_ROLES = "MCplayer,MCadmin";
      # /ask - LLM-backed support, answered privately from the generated
      # manifest. Empty ASK_ENDPOINT or ASK_TOKEN disables the command, so a
      # half-configured deploy stays quiet rather than erroring at players.
      #
      # The manifest is read from the WORKING COPY, not the Nix store, so
      # /askreload picks up a regenerated file without a rebuild.
      #
      # ⚠️ ASK_TOKEN lands in the Nix store, which is world-readable — the same
      # weakness TG_TOKEN and DISCORD_TOKEN above already have. It is the
      # gateway's own bearer, not a provider key, so the blast radius is
      # "someone with a shell on the VPS can spend the prepaid balance". Worth
      # moving all four to an EnvironmentFile (as system/app/litellm.nix does)
      # in a follow-up; doing it for one token only would be theatre.
      ASK_ENDPOINT = lib.optionalString askEnable
        "http://${litellmHost}:${toString litellmPort}/v1/chat/completions";
      ASK_TOKEN = lib.optionalString askEnable askToken;
      ASK_MODEL = systemSettings.akucraftAskModel or "akucraft-support";
      ASK_MANIFEST =
        "/home/${username}/.dotfiles/docs/akunito/infrastructure/services/akucraft-manifest.md";
      ASK_DAILY_QUOTA = toString (systemSettings.akucraftAskDailyQuota or 25);
      # { Akunito = 60; } -> "Akunito:60". Keyed by Minecraft name, so it reads
      # the way it is meant ("Akunito gets 60") rather than by Discord snowflake.
      ASK_QUOTA_OVERRIDES = lib.concatStringsSep "," (lib.mapAttrsToList
        (n: v: "${n}:${toString v}")
        (systemSettings.akucraftAskQuotaOverrides or { }));
      ASK_ADMIN_ROLES = "MCadmin";
      # Confine /ask to the Minecraft category. Empty = anywhere in the guild.
      # /askreload is deliberately NOT confined: it is already role-gated, and
      # admins run it from moderator channels, which sit outside the category.
      ASK_CATEGORY = secrets.akucraftDiscordMinecraftCategoryId or "";
      # Follow-up questions. Bounded on both axes so a player's questions are a
      # conversation that expires, not a permanent transcript on disk.
      # Generous on purpose: the backing model reasons before answering and
      # bills that as output. An open-ended "what should I do next?" spent 1200
      # tokens thinking and returned NOTHING at a lower ceiling.
      ASK_MAX_TOKENS = toString (systemSettings.akucraftAskMaxTokens or 3000);
      ASK_HISTORY_TURNS = toString (systemSettings.akucraftAskHistoryTurns or 10);
      ASK_HISTORY_TTL_HOURS = toString (systemSettings.akucraftAskHistoryTtlHours or 24);
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
      # Reading the user list is needed BEFORE either of the others: the script
      # checks whether the guest already exists, then looks up their id to mint
      # the key against. Granting only the two mutating commands - as this did
      # until 2026-08-16 - let it create the user and then abort with an empty
      # id, leaving a half-made guest and an invite that never arrived.
      { command = "/run/current-system/sw/bin/headscale users list";           options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/headscale users list *";         options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/headscale users create *";       options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/headscale preauthkeys create *"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
