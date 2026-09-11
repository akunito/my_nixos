# infra-notify — deploy announcements + post-deploy check for "Infra Alerts"
#
# Installs `infra-notify`, called by install.sh and autoSystemUpdate.sh when a
# deploy ends (ok / warn / failed / rollback). The NODE itself announces, so a
# VPS deploy that restarts the bot still gets reported, and a NAS deploy does
# not depend on the VPS bot being up. The message carries a post-deploy check
# run locally (docker daemons, failed units, containers not running, disk) plus
# the node's active alerts fetched from the bot's relay.
#
# Transport (AINF-368 decision):
#   - nodes that hold the bot token (VPS, NAS, DESK, X13): straight to the
#     Telegram API, token in /etc/secrets/infra-notify.env (root 0400 — the
#     callers run under sudo/root)
#   - secrets-free nodes (LAPTOP_A, DESK_A, YOGA): POST to the bot's relay on
#     the VPS Tailscale IP; the bot identifies them by source IP. No token on
#     Aga's machines, on purpose.
#
# Flags: infraNotifyEnable, infraNodeName (Prometheus node label),
#        infraBotUrl (relay base URL, e.g. http://100.64.0.6:8765)
#
#   infra-notify deploy --status ok --profile NAS_PROD --duration 252 \
#       --gen-before 57 --gen-after 58 --commit 1adf7162 --by akunito --via install.sh
#   infra-notify check          # print the health block (what a deploy would report)
#   infra-notify send "<text>"  # raw HTML to the Deploys topic (tests)

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  enabled = systemSettings.infraNotifyEnable or false;
  token = systemSettings.grafanaTelegramBotToken or "";
  chatId = systemSettings.grafanaTelegramChatId or "";
  threadId = systemSettings.infraTelegramDeploysThreadId or "";
  relayUrl = systemSettings.infraBotUrl or "";
  node = systemSettings.infraNodeName or systemSettings.hostname;
  direct = token != "" && chatId != "";
  rootful = config.virtualisation.docker.enable;
  rootless = config.virtualisation.docker.rootless.enable;
  username = userSettings.username;

  script = pkgs.writeShellApplication {
    name = "infra-notify";
    runtimeInputs = with pkgs; [ coreutils curl jq gawk gnused systemd util-linux hostname ];
    text = ''
      NODE="${node}"
      CHAT_ID="${chatId}"
      THREAD_ID="${threadId}"
      RELAY_URL="${relayUrl}"
      DOCKER_ROOTFUL="${lib.boolToString rootful}"
      DOCKER_ROOTLESS="${lib.boolToString rootless}"
      DOCKER_USER="${username}"
      TOKEN_FILE="/etc/secrets/infra-notify.env"
      HOST=$(hostname)

      esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

      # --- run something inside the docker user's systemd --user manager ---
      userctl() {
        local uid; uid=$(id -u "$DOCKER_USER")
        if [ "$(id -u)" = 0 ]; then
          runuser -u "$DOCKER_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
        elif [ "$(id -un)" = "$DOCKER_USER" ]; then
          env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
        else
          return 1
        fi
      }
      docker_bin() { command -v docker 2>/dev/null || { [ -x /run/current-system/sw/bin/docker ] && echo /run/current-system/sw/bin/docker; } || true; }

      # --- the post-deploy check: one line per item, led first ---
      health() {
        local worst=0
        # docker daemons
        if [ "$DOCKER_ROOTFUL" = true ]; then
          if systemctl is-active --quiet docker.service; then echo "🟢 docker rootful up"; else echo "🔴 docker rootful DOWN"; worst=2; fi
        fi
        if [ "$DOCKER_ROOTLESS" = true ]; then
          if userctl systemctl --user is-active --quiet docker.service 2>/dev/null; then echo "🟢 docker rootless up"; else echo "🔴 docker rootless DOWN"; worst=2; fi
        fi
        # containers not running (exited/dead/restarting): usually someone's
        # dev stack, so yellow — but named, so a crashed prod container is visible
        local dbin; dbin=$(docker_bin)
        if [ -n "$dbin" ]; then
          local stopped=""
          if [ "$DOCKER_ROOTFUL" = true ]; then
            stopped+=$("$dbin" ps -a --filter status=exited --filter status=dead --filter status=restarting --format '{{.Names}}' 2>/dev/null | head -20 || true)
          fi
          if [ "$DOCKER_ROOTLESS" = true ]; then
            local uid; uid=$(id -u "$DOCKER_USER")
            stopped+=$'\n'$(userctl env DOCKER_HOST="unix:///run/user/$uid/docker.sock" "$dbin" ps -a --filter status=exited --filter status=dead --filter status=restarting --format '{{.Names}}' 2>/dev/null | head -20 || true)
          fi
          stopped=$(printf '%s\n' "$stopped" | sed '/^$/d')
          if [ -n "$stopped" ]; then
            echo "🟡 containers not running: $(printf '%s' "$stopped" | tr '\n' ' ' | esc)"; [ $worst -lt 1 ] && worst=1
          elif [ "$DOCKER_ROOTFUL" = true ] || [ "$DOCKER_ROOTLESS" = true ]; then
            echo "🟢 all containers running"
          fi
        fi
        # failed units (system + the docker user's manager)
        local failed; failed=$(systemctl --failed --plain --no-legend 2>/dev/null | awk '{print $1}')
        local ufailed; ufailed=$(userctl systemctl --user --failed --plain --no-legend 2>/dev/null | awk '{print $1}' || true)
        if [ -z "$failed$ufailed" ]; then
          echo "🟢 no failed units"
        else
          echo "🔴 failed units: $(printf '%s %s' "$failed" "$ufailed" | tr '\n' ' ' | esc)"; worst=2
        fi
        # disk: real filesystems only
        local worstfs="" worstpct=0 bad=""
        while read -r _ _ _ _ pct mnt; do
          pct=''${pct%\%}
          [ "$pct" -gt "$worstpct" ] && { worstpct=$pct; worstfs=$mnt; }
          [ "$pct" -ge 85 ] && bad+="$mnt $pct% "
        done < <(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs -x fuse.portal 2>/dev/null | tail -n +2)
        if [ "$worstpct" -ge 95 ]; then echo "🔴 disk: $bad"; worst=2
        elif [ "$worstpct" -ge 85 ]; then echo "🟡 disk: $bad"; [ $worst -lt 1 ] && worst=1
        else echo "🟢 disk ok (max $worstpct% $worstfs)"; fi
        # active alerts for this node, via the bot relay (best effort)
        if [ -n "$RELAY_URL" ]; then
          local resp
          if resp=$(curl -fsS --max-time 8 "$RELAY_URL/alerts?node=$NODE" 2>/dev/null); then
            local crit warn
            crit=$(printf '%s' "$resp" | jq -r '[.alerts[] | select(.severity=="critical" and .muted==false and .inhibited==false) | .alertname] | unique | join(", ")')
            warn=$(printf '%s' "$resp" | jq -r '[.alerts[] | select(.severity!="critical" and .muted==false and .inhibited==false) | .alertname] | unique | length')
            if [ -n "$crit" ]; then echo "🔴 active criticals: $(printf '%s' "$crit" | esc)"; worst=2
            elif [ "$warn" != "0" ]; then echo "🟡 $warn active warning(s), no criticals"; [ $worst -lt 1 ] && worst=1
            else echo "🟢 no active alerts"; fi
          else
            echo "⚪ alerts: relay unreachable"
          fi
        fi
        return $worst
      }

      # --- transports ---
      send_direct() {
        # shellcheck disable=SC1090
        . "$TOKEN_FILE"
        curl -fsS --max-time 15 -o /dev/null -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
          --data-urlencode "chat_id=$CHAT_ID" \
          ''${THREAD_ID:+--data-urlencode "message_thread_id=$THREAD_ID"} \
          --data-urlencode "parse_mode=HTML" \
          --data-urlencode "disable_web_page_preview=true" \
          --data-urlencode "text=$1"
      }
      send_relay() {
        jq -n --arg text "$1" --arg hostname "$HOST" '{text:$text, hostname:$hostname}' \
          | curl -fsS --max-time 15 -o /dev/null -X POST -H 'Content-Type: application/json' --data-binary @- "$RELAY_URL/deploy"
      }
      send() {
        if [ -r "$TOKEN_FILE" ]; then
          send_direct "$1" && return 0
          echo "infra-notify: direct Telegram send failed" >&2
        fi
        if [ -n "$RELAY_URL" ]; then
          send_relay "$1" && return 0
          echo "infra-notify: relay send failed ($RELAY_URL)" >&2
        fi
        [ -r "$TOKEN_FILE" ] || [ -n "$RELAY_URL" ] || echo "infra-notify: no transport configured (no token file, no infraBotUrl)" >&2
        return 1
      }

      fmt_duration() {
        local s=''${1:-0}
        if [ "$s" -ge 3600 ]; then printf '%dh%02dm' $((s/3600)) $((s%3600/60))
        elif [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s/60)) $((s%60))
        else printf '%ds' "$s"; fi
      }

      cmd=''${1:-help}; shift || true
      case "$cmd" in
        check)
          health; echo "worst=$?" ;;
        send)
          send "$*" ;;
        deploy)
          status=unknown profile="?" duration="" gb="" ga="" commit="" by="" via="" note=""
          while [ $# -gt 0 ]; do
            case "$1" in
              --status) status=$2; shift 2 ;;
              --profile) profile=$2; shift 2 ;;
              --duration) duration=$2; shift 2 ;;
              --gen-before) gb=$2; shift 2 ;;
              --gen-after) ga=$2; shift 2 ;;
              --commit) commit=$2; shift 2 ;;
              --by) by=$2; shift 2 ;;
              --via) via=$2; shift 2 ;;
              --note) note=$2; shift 2 ;;
              *) echo "infra-notify: unknown arg $1" >&2; shift ;;
            esac
          done
          case "$status" in
            ok) head="✅ OK" ;;
            warn) head="⚠️ OK WITH WARNINGS" ;;
            failed) head="❌ FAILED" ;;
            rollback) head="↩️ ROLLED BACK" ;;
            *) head="❔ $status" ;;
          esac
          gens=""
          if [ -n "$gb" ] && [ -n "$ga" ] && [ "$gb" != "$ga" ]; then gens="gen $gb → $ga"
          elif [ -n "$ga" ]; then gens="gen $ga"; fi
          meta=""
          [ -n "$gens" ] && meta+="$gens · "
          [ -n "$commit" ] && meta+="<code>$(printf '%s' "$commit" | esc)</code> · "
          [ -n "$duration" ] && meta+="$(fmt_duration "$duration") · "
          meta+="$(printf '%s' "''${by:-?}" | esc) via $(printf '%s' "''${via:-?}" | esc)"
          text="🚀 <b>Deploy $head</b> · <b>$(printf '%s' "$profile" | esc)</b> · $(printf '%s' "$HOST" | esc)"$'\n'"$meta"
          [ -n "$note" ] && text+=$'\n'"<i>$(printf '%s' "$note" | esc)</i>"
          # a failed rebuild left the OLD system running: the check still says
          # something useful (did the rollback leave everything up?)
          body=$(health || true)
          text+=$'\n'"<b>Post-deploy check</b>"$'\n'"$body"
          send "$text" || true
          echo "infra-notify: deploy announced ($status)" ;;
        *)
          echo "usage: infra-notify deploy --status ok|warn|failed|rollback [--profile P] [--duration S] [--gen-before N] [--gen-after M] [--commit SHA] [--by U] [--via X] [--note T]"
          echo "       infra-notify check | infra-notify send <html>" ;;
      esac
    '';
  };
in
lib.mkIf enabled {
  environment.systemPackages = [ script ];

  environment.etc."secrets/infra-notify.env" = lib.mkIf direct {
    text = "TELEGRAM_BOT_TOKEN=${token}\n";
    mode = "0400";
    user = "root";
  };
}
