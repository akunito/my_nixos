# claude-sync hub — the always-on side of Claude Code state sync (VPS_PROD).
#
# Clients (DESK, LAPTOP_X13, DESK_W11) reach ~/claude-sync over Tailscale with a
# dedicated key that is pinned to `claude-sync-shell`, a forced command that
# only allows:
#   - rsync --server into claude-sync/sessions/ or claude-sync/heartbeat/
#     (no --delete: clients can only add or update, never wipe the hub)
#   - git upload-pack / receive-pack on claude-sync/state.git
#   - ping
#
# Layout (user home, 0700):
#   claude-sync/state.git    bare repo: memory, skills, commands, plans, agents
#   claude-sync/sessions/    projects/<key>/<uuid>.jsonl + tool-results, tasks/
#   claude-sync/heartbeat/   one file per machine, touched on every push
#
# Daily maintenance (root): age out sessions past the retention window (one day
# before the clients' cleanupPeriodDays so nothing is resurrected), alert the
# Infra Alerts Telegram on pending *.conflict-* files in the state repo and on
# heartbeats older than 14 days, git gc.
#
# Flags: claudeSyncHubEnable, claudeSyncHubKeys, claudeSyncHubDir,
#        claudeSyncRetentionDays. Client side: user/app/claude-code/claude-sync.nix
# Docs: docs/akunito/infrastructure/services/claude-sync.md

{ config, lib, pkgs, systemSettings, userSettings, ... }:

let
  enabled = systemSettings.claudeSyncHubEnable or false;
  keys = systemSettings.claudeSyncHubKeys or [ ];
  user = userSettings.username;
  home = "/home/${user}";
  dir = systemSettings.claudeSyncHubDir or "claude-sync";
  hub = "${home}/${dir}";
  retention = systemSettings.claudeSyncRetentionDays or 90;
  staleDays = 14;

  shell = pkgs.writeShellApplication {
    name = "claude-sync-shell";
    runtimeInputs = with pkgs; [ rsync git coreutils gnugrep util-linux ];
    bashOptions = [ "nounset" "pipefail" ];
    text = ''
      DIR="${dir}"
      STATE="${hub}/state.git"
      cmd="''${SSH_ORIGINAL_COMMAND:-}"
      deny() { logger -t claude-sync-shell "DENY [$*]: $cmd"; echo "claude-sync-shell: denied" >&2; exit 1; }

      case "$cmd" in
        ping) echo pong; exit 0 ;;
        "rsync --server "*)
          case "$cmd" in
            *--delete*|*--remove-source-files*|*--rsync-path*|*'..'*|*"'"*|*'"'*|*'$'*|*'`'*|*';'*) deny flags ;;
          esac
          last="''${cmd##* }"
          case "$last" in
            "$DIR/sessions"|"$DIR/sessions/"|"$DIR/heartbeat"|"$DIR/heartbeat/") ;;
            *) deny path ;;
          esac
          read -ra parts <<<"$cmd"
          exec rsync "''${parts[@]:1}" ;;
        "git-upload-pack '$STATE'"|"git-receive-pack '$STATE'")
          exec git-shell -c "$cmd" ;;
        *) deny unknown ;;
      esac
    '';
  };

  maintenance = pkgs.writeShellApplication {
    name = "claude-sync-hub-maintenance";
    runtimeInputs = with pkgs; [ coreutils findutils gnugrep gnused git util-linux ];
    bashOptions = [ "nounset" "pipefail" ];
    text = ''
      HUB="${hub}"
      USER_="${user}"
      VAR=/var/lib/claude-sync-hub
      mkdir -p "$VAR"
      NOTIFY=/run/current-system/sw/bin/infra-notify
      esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
      send() { if [ -x "$NOTIFY" ]; then "$NOTIFY" send "$1" || true; else logger -t claude-sync-hub "$1"; fi; }

      # 1. retention: sessions older than (retention - 1) days; leftovers of partial transfers
      if [ -d "$HUB/sessions" ]; then
        find "$HUB/sessions" -type f -mtime +$(( ${toString retention} - 1 )) -delete
        find "$HUB/sessions" -type d -name '.rsync-partial' -mtime +2 -exec rm -rf {} + 2>/dev/null || true
        find "$HUB/sessions" -mindepth 1 -type d -empty -delete
      fi

      # 2. memory conflicts pending in the state repo (alert only when the set changes)
      if [ -d "$HUB/state.git" ]; then
        conflicts=$(runuser -u "$USER_" -- git --git-dir="$HUB/state.git" ls-tree -r --name-only main 2>/dev/null | grep '\.conflict-' || true)
        prev=$(cat "$VAR/conflicts.last" 2>/dev/null || true)
        if [ "$conflicts" != "$prev" ]; then
          printf '%s' "$conflicts" >"$VAR/conflicts.last"
          if [ -n "$conflicts" ]; then
            n=$(printf '%s\n' "$conflicts" | grep -c .)
            send "🧠 <b>claude-sync</b>: $n memory conflict file(s) waiting for a merge
<pre>$(printf '%s\n' "$conflicts" | head -10 | esc)</pre>
Open Claude on any synced machine: the SessionStart hook lists them and asks Claude to merge."
          else
            send "🧠 <b>claude-sync</b>: memory conflicts resolved."
          fi
        fi
        runuser -u "$USER_" -- git --git-dir="$HUB/state.git" gc --auto --quiet 2>/dev/null || true
      fi

      # 3. heartbeats: a machine that has not pushed for ${toString staleDays} days (once per machine)
      if [ -d "$HUB/heartbeat" ]; then
        for hb in "$HUB"/heartbeat/*; do
          [ -f "$hb" ] || continue
          m=$(basename "$hb")
          if [ -n "$(find "$hb" -mtime +${toString staleDays})" ]; then
            if [ ! -f "$VAR/stale.$m" ]; then
              send "🧠 <b>claude-sync</b>: <b>$m</b> has not synced since $(date -r "$hb" '+%F') — its memory/session changes are not on the hub."
              touch "$VAR/stale.$m"
            fi
          else
            rm -f "$VAR/stale.$m"
          fi
        done
      fi
    '';
  };
in
lib.mkIf enabled {
  users.users.${user}.openssh.authorizedKeys.keys =
    map (k: "restrict,command=\"${shell}/bin/claude-sync-shell\" ${k}") keys;

  systemd.tmpfiles.rules = [
    "d ${hub} 0700 ${user} users -"
    "d ${hub}/sessions 0700 ${user} users -"
    "d ${hub}/heartbeat 0700 ${user} users -"
    "d /var/lib/claude-sync-hub 0700 root root -"
  ];

  systemd.services.claude-sync-hub-init = {
    description = "claude-sync hub: create the bare state repo";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = "users";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -d "${hub}/state.git" ]; then
        ${pkgs.git}/bin/git init --quiet --bare -b main "${hub}/state.git"
      fi
    '';
  };

  systemd.services.claude-sync-hub-maintenance = {
    description = "claude-sync hub: retention, conflict + heartbeat alerts, gc";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${maintenance}/bin/claude-sync-hub-maintenance";
    };
  };
  systemd.timers.claude-sync-hub-maintenance = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:20:00";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };
}
