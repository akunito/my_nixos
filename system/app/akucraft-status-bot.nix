# AkuCraft Telegram status bot
#
# Polls the two Minecraft containers (survival + creative) every 2 minutes and
# posts to the AkuCraft Telegram group when a server goes ONLINE/OFFLINE and
# when players join or leave (via RCON `list`).
#
# The Minecraft stack is rootless docker under user akunito (~/.homelab/minecraft*),
# so the service runs as that user against /run/user/1000/docker.sock (lingering
# is enabled on VPS_PROD, so the socket exists without an active session).
#
# Gated by systemSettings.akucraftStatusBotEnable + non-empty telegram secrets:
#   secrets/domains.nix: akucraftTelegramBotToken, akucraftTelegramChatId
#
# State (last known status/players per server) lives in /var/lib/akucraft-status.

{ config, lib, pkgs, systemSettings, ... }:

let
  secrets = import ../../secrets/domains.nix;
  token = secrets.akucraftTelegramBotToken or "";
  chatId = secrets.akucraftTelegramChatId or "";
  enabled = (systemSettings.akucraftStatusBotEnable or false) && token != "" && chatId != "";

  statusScript = pkgs.writeShellScript "akucraft-telegram-status" ''
    set -u
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.curl pkgs.docker ]}
    export DOCKER_HOST=unix:///run/user/1000/docker.sock

    STATE_DIR="''${STATE_DIRECTORY:-/var/lib/akucraft-status}"

    send() {
      curl -s -m 15 "https://api.telegram.org/bot${token}/sendMessage" \
        --data-urlencode "chat_id=${chatId}" \
        --data-urlencode "text=$1" > /dev/null || true
    }

    check_server() {
      local label="$1" container="$2" address="$3"
      local state_file="$STATE_DIR/$container.state"
      local players_file="$STATE_DIR/$container.players"

      local health
      health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo absent)
      local status=offline
      [ "$health" = "healthy" ] && status=online

      local prev
      prev=$(cat "$state_file" 2>/dev/null || echo unknown)

      if [ "$status" != "$prev" ]; then
        if [ "$status" = "online" ]; then
          send "🟢 AkuCraft $label is ONLINE — connect: $address"
        elif [ "$prev" = "online" ]; then
          send "🔴 AkuCraft $label went OFFLINE"
        fi
        echo "$status" > "$state_file"
      fi

      # Player join/leave announcements (only while online)
      if [ "$status" = "online" ]; then
        local players count
        players=$(docker exec "$container" rcon-cli list 2>/dev/null \
          | sed -n 's/.*players online:\s*//p' | tr -d '\r' \
          | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^$' | sort)
        count=$(printf '%s' "$players" | grep -c . || true)
        local prev_players
        prev_players=$(cat "$players_file" 2>/dev/null || true)

        if [ "$players" != "$prev_players" ] && [ "$prev" = "online" ]; then
          local joined left
          joined=$(comm -13 <(printf '%s\n' "$prev_players" | grep -v '^$') <(printf '%s\n' "$players" | grep -v '^$') | tr '\n' ' ')
          left=$(comm -23 <(printf '%s\n' "$prev_players" | grep -v '^$') <(printf '%s\n' "$players" | grep -v '^$') | tr '\n' ' ')
          [ -n "''${joined// }" ] && send "🎮 $joined joined $label ($count online)"
          [ -n "''${left// }" ] && send "👋 $left left $label ($count online)"
        fi
        printf '%s' "$players" > "$players_file"
      else
        rm -f "$players_file"
      fi
    }

    check_server "Survival" "minecraft" "akucraft.local.akunito.com"
    check_server "Creative" "minecraft-creative" "akucraft.local.akunito.com:25566"
  '';
in
lib.mkIf enabled {
  systemd.services.akucraft-status-bot = {
    description = "AkuCraft Telegram status notifications";
    serviceConfig = {
      Type = "oneshot";
      User = "akunito";
      ExecStart = statusScript;
      StateDirectory = "akucraft-status";
    };
  };

  systemd.timers.akucraft-status-bot = {
    description = "Poll AkuCraft servers for Telegram status updates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "2min";
      RandomizedDelaySec = "10s";
    };
  };
}
