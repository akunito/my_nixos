# claude-sync — keep ~/.claude in step across machines through a hub on the VPS.
#
# Wrapped by claude-sync-pkg.nix, which prepends the configuration block
# (HUB_*, MACHINE, REAL_CLAUDE, RETENTION_DAYS, KEY) and the runtime PATH.
#
# Two channels, one hub (VPS_PROD, Tailscale only, dedicated restricted key):
#   state    git repo rooted at ~/.claude with a whitelist .gitignore:
#            projects/*/memory, skills, commands, plans, agents, CLAUDE.md,
#            history.jsonl. Merged; MEMORY.md + history.jsonl union-merge;
#            any other conflict is resolved by keeping BOTH versions
#            (hub copy as the file, local copy as <file>.conflict-<MACHINE>).
#   sessions rsync, additive, single writer per session UUID: transcripts
#            projects/<key>/<uuid>.jsonl + <uuid>/tool-results + tasks/<uuid>.
#            Ownership sidecar <uuid>.owner names the machine that writes it.
#            Resuming a foreign session goes through --fork-session (wrapper).
#
# Subcommands
#   init            first run on a machine: key, repo, merge with hub, push
#   sync            commit + pull + push both channels (timer / manual)
#   pull | push     one direction only
#   status          what would sync, conflicts pending, hub reachability
#   pubkey          print this machine's hub public key
#   hook-start      Claude Code SessionStart hook (stdin JSON)
#   hook-stop       Claude Code Stop hook (stdin JSON) — background push
#   hook-end        Claude Code SessionEnd hook (stdin JSON) — 1.5 s budget!
#   wrap ARGS...    what the `claude` wrapper runs: pull, decide fork, exec

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-sync"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-sync"
KEY="${KEY:-$CONF_DIR/key}"
LOG="$STATE_DIR/log"
LOCK="$STATE_DIR/lock"
HUB="$HUB_USER@$HUB_HOST"
HUB_SESSIONS="$HUB_DIR/sessions"
HUB_HEARTBEAT="$HUB_DIR/heartbeat"
STATE_URL="ssh://$HUB_USER@$HUB_HOST:$HUB_PORT/home/$HUB_USER/$HUB_DIR/state.git"
# sessions modified within this window are candidates for a full push
PUSH_WINDOW_DAYS="${PUSH_WINDOW_DAYS:-3}"
# warn locally when no successful sync for this long while attempts were made
STALE_SECS="${STALE_SECS:-21600}"

mkdir -p "$STATE_DIR" "$CONF_DIR"
chmod 700 "$CONF_DIR"

SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=6
          -o ServerAliveInterval=10 -o ServerAliveCountMax=3
          -o StrictHostKeyChecking=accept-new -p "$HUB_PORT")
export GIT_SSH_COMMAND="ssh ${SSH_OPTS[*]}"
RSYNC_SSH="ssh ${SSH_OPTS[*]}"

log() {
  local ts; ts=$(date '+%F %T')
  echo "$ts [$MACHINE] $*" >>"$LOG"
  # keep the log small
  if [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 1000000 ]; then
    tail -n 2000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
  fi
}

notify() {
  # $1 summary, $2 body. Desktop toast when there is a display, always logged.
  log "NOTIFY: $1 — $2"
  if command -v notify-send >/dev/null 2>&1 && { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; }; then
    notify-send -u normal -t 15000 -i dialog-warning "claude-sync: $1" "$2" || true
  fi
}

die() { echo "claude-sync: $*" >&2; log "ERROR: $*"; exit 1; }

git_state() { git -C "$CLAUDE_DIR" "$@"; }

hub_reachable() {
  ssh "${SSH_OPTS[@]}" "$HUB" ping >/dev/null 2>&1
}

# One probe before a batch of connections. A rejected key means the hub is not
# provisioned for this machine yet: automatic runs (hooks, timer, wrapper —
# CLAUDE_SYNC_AUTO=1) back off for 6 h so fail2ban on the VPS never sees a
# stream of failed logins. Manual `claude-sync sync|pull|push` always tries.
AUTH_BACKOFF_SECS=21600
probe_hub() {
  local out
  out=$(ssh "${SSH_OPTS[@]}" "$HUB" ping 2>&1 || true)
  case "$out" in
    *pong*) rm -f "$STATE_DIR/auth-failed"; return 0 ;;
    *"Permission denied"*)
      date +%s >"$STATE_DIR/auth-failed"
      log "hub: key not authorized — automatic runs back off ${AUTH_BACKOFF_SECS}s (add \`claude-sync pubkey\` to claudeSyncHubKeys)"
      return 2 ;;
    *) log "hub: unreachable (${out%%$'\n'*})"; return 1 ;;
  esac
}
backoff_active() {
  [ "${CLAUDE_SYNC_AUTO:-0}" = 1 ] || return 1
  local t; t=$(cat "$STATE_DIR/auth-failed" 2>/dev/null || echo 0)
  [ $(( $(date +%s) - t )) -lt "$AUTH_BACKOFF_SECS" ]
}

mark_ok()   { date +%s >"$STATE_DIR/last-ok"; rm -f "$STATE_DIR/first-fail"; }
mark_fail() {
  local now; now=$(date +%s)
  [ -f "$STATE_DIR/first-fail" ] || echo "$now" >"$STATE_DIR/first-fail"
  local first; first=$(cat "$STATE_DIR/first-fail")
  if [ $((now - first)) -ge "$STALE_SECS" ] && [ ! -f "$STATE_DIR/stale-notified" ]; then
    notify "hub unreachable" "No sync with $HUB_HOST for $(( (now - first) / 3600 )) h. Memory and sessions are only local."
    touch "$STATE_DIR/stale-notified"
  fi
}
clear_stale() { rm -f "$STATE_DIR/stale-notified"; }

# ---------------------------------------------------------------- state (git)

GITIGNORE_CONTENT='# claude-sync: everything is ignored unless whitelisted below.
*
!.gitignore
!.gitattributes
!CLAUDE.md
!history.jsonl
!projects/
projects/*
!projects/*/
projects/*/*
!projects/*/memory/
!projects/*/memory/**
!skills/
!skills/**
!commands/
!commands/**
!plans/
!plans/**
!agents/
!agents/**
'
GITATTRIBUTES_CONTENT='# claude-sync: append-only files merge line-wise, never conflict.
projects/*/memory/MEMORY.md merge=union
history.jsonl merge=union
* -text
'

write_if_differs() {
  local path=$1 content=$2
  if [ ! -f "$path" ] || [ "$(cat "$path")" != "$(printf '%s' "$content")" ]; then
    printf '%s' "$content" >"$path"
  fi
}

ensure_repo() {
  mkdir -p "$CLAUDE_DIR"
  write_if_differs "$CLAUDE_DIR/.gitignore" "$GITIGNORE_CONTENT"
  write_if_differs "$CLAUDE_DIR/.gitattributes" "$GITATTRIBUTES_CONTENT"
  if [ ! -d "$CLAUDE_DIR/.git" ]; then
    git_state init -q -b main
    log "state repo created"
  fi
  git_state config user.name "$MACHINE"
  git_state config user.email "claude-sync@$MACHINE"
  git_state config merge.conflictStyle merge
  git_state config pull.rebase false
  git_state config gc.auto 256
  if git_state remote get-url hub >/dev/null 2>&1; then
    git_state remote set-url hub "$STATE_URL"
  else
    git_state remote add hub "$STATE_URL"
  fi
}

commit_local() {
  # Commit whatever the whitelist sees. Silent when clean.
  git_state add -A >/dev/null 2>&1 || true
  if ! git_state diff --cached --quiet 2>/dev/null; then
    git_state commit -q -m "$MACHINE $(date '+%F %H:%M')" >/dev/null 2>&1 || true
    log "state: committed local changes"
  elif ! git_state rev-parse --verify HEAD >/dev/null 2>&1; then
    git_state commit -q --allow-empty -m "$MACHINE init" >/dev/null 2>&1 || true
  fi
}

resolve_conflicts_keep_both() {
  # In a stopped merge: hub version becomes the file, local version is kept
  # alongside as <file>.conflict-<MACHINE>. Never loses either side.
  local f conflicted=()
  while IFS= read -r f; do conflicted+=("$f"); done < <(git_state diff --name-only --diff-filter=U)
  [ ${#conflicted[@]} -gt 0 ] || return 0
  for f in "${conflicted[@]}"; do
    if git_state show ":2:$f" >"$CLAUDE_DIR/$f.conflict-$MACHINE" 2>/dev/null; then :; fi
    if git_state show ":3:$f" >"$CLAUDE_DIR/$f" 2>/dev/null; then
      :
    else
      # deleted on the hub: keep our version as the file again
      cp -f "$CLAUDE_DIR/$f.conflict-$MACHINE" "$CLAUDE_DIR/$f" 2>/dev/null || true
    fi
    git_state add -f -- "$f" "$f.conflict-$MACHINE" >/dev/null 2>&1 || true
  done
  git_state commit -q -m "merge: kept both versions (${conflicted[*]}) on $MACHINE" >/dev/null 2>&1 || true
  notify "memory conflict" "Both versions kept: ${conflicted[*]} (+ .conflict-$MACHINE). Claude will merge them next session."
}

pull_state() {
  ensure_repo
  commit_local
  if ! git_state fetch -q hub main 2>>"$LOG"; then
    # empty hub repo is fine on first init
    if git_state ls-remote --exit-code hub >/dev/null 2>&1; then return 1; fi
    if git_state ls-remote hub >/dev/null 2>&1; then return 0; fi
    return 1
  fi
  if ! git_state rev-parse --verify hub/main >/dev/null 2>&1; then return 0; fi
  if git_state merge-base --is-ancestor hub/main HEAD 2>/dev/null; then return 0; fi
  local before; before=$(git_state rev-parse HEAD)
  if ! git_state merge -q --no-edit --allow-unrelated-histories hub/main >/dev/null 2>>"$LOG"; then
    resolve_conflicts_keep_both
    if git_state diff --name-only --diff-filter=U | grep -q .; then
      git_state merge --abort >/dev/null 2>&1 || true
      notify "memory merge failed" "Automatic merge aborted; run: claude-sync status"
      return 1
    fi
  fi
  [ "$(git_state rev-parse HEAD)" != "$before" ] && log "state: merged hub/main"
  return 0
}

push_state() {
  ensure_repo
  commit_local
  if git_state rev-parse --verify hub/main >/dev/null 2>&1 &&
     git_state merge-base --is-ancestor HEAD hub/main 2>/dev/null; then
    return 0 # nothing new
  fi
  if git_state push -q hub main 2>>"$LOG"; then
    log "state: pushed"
    return 0
  fi
  # non fast-forward: someone else pushed. Merge, then retry once.
  pull_state || return 1
  git_state push -q hub main 2>>"$LOG" && log "state: pushed after merge"
}

# ------------------------------------------------------------ sessions (rsync)

owner_of() { # $1 = path to <uuid>.jsonl
  local o="${1%.jsonl}.owner"
  [ -f "$o" ] && tr -d '[:space:]' <"$o" || true
}

owned_here() { # true when this machine may write the session
  local o; o=$(owner_of "$1")
  [ -z "$o" ] || [ "$o" = "$MACHINE" ]
}

session_paths() { # $1 = path to <uuid>.jsonl → relative paths to push
  local jsonl=$1 rel dir uuid
  rel=${jsonl#"$CLAUDE_DIR"/}
  dir=$(dirname "$rel"); uuid=$(basename "$rel" .jsonl)
  echo "$rel"
  echo "$dir/$uuid.owner"
  [ -d "$CLAUDE_DIR/$dir/$uuid" ] && echo "$dir/$uuid"
  [ -d "$CLAUDE_DIR/tasks/$uuid" ] && echo "tasks/$uuid"
  return 0
}

push_sessions() { # args: explicit jsonl paths; none = every owned session in the window
  local -a jsonls=()
  if [ $# -gt 0 ]; then
    jsonls=("$@")
  else
    while IFS= read -r f; do jsonls+=("$f"); done < <(
      find "$CLAUDE_DIR/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime "-$PUSH_WINDOW_DAYS" 2>/dev/null)
  fi
  local list="$STATE_DIR/push-list"; : >"$list"
  local j foreign=0
  for j in "${jsonls[@]}"; do
    [ -f "$j" ] || continue
    owned_here "$j" || { foreign=$((foreign + 1)); continue; }
    echo "$MACHINE" >"${j%.jsonl}.owner"
    session_paths "$j" >>"$list"
  done
  [ -s "$list" ] || return 0
  [ "$foreign" -gt 0 ] && log "sessions: $foreign foreign session(s) left to their owners"
  if rsync -a -r --relative --partial --partial-dir=.rsync-partial --timeout=90 --files-from="$list" \
       -e "$RSYNC_SSH" "$CLAUDE_DIR/" "$HUB:$HUB_SESSIONS/" 2>>"$LOG"; then
    log "sessions: pushed $(grep -c '\.jsonl$' "$list") session(s), $(wc -l <"$list") paths"
    return 0
  fi
  return 1
}

pull_sessions() {
  # Additive: never deletes locally, never overwrites a newer local file
  # (the session open right now is always newer than the hub copy).
  # Excludes everything the git channel owns.
  mkdir -p "$CLAUDE_DIR/projects" "$CLAUDE_DIR/tasks"
  rsync -a --update --timeout=90 --exclude='memory/' --exclude='.rsync-partial/' \
    -e "$RSYNC_SSH" "$HUB:$HUB_SESSIONS/" "$CLAUDE_DIR/" 2>>"$LOG"
}

push_heartbeat() {
  local hb="$STATE_DIR/heartbeat"; mkdir -p "$hb"
  date '+%F %T' >"$hb/$MACHINE"
  rsync -a --timeout=30 -e "$RSYNC_SSH" "$hb/" "$HUB:$HUB_HEARTBEAT/" 2>>"$LOG" || true
}

# ------------------------------------------------------------------ composite

with_lock() { # $1 = -n (skip if busy) or -w (wait) ; rest = command
  local mode=$1; shift
  exec 9>"$LOCK"
  if [ "$mode" = -n ]; then
    flock -n 9 || { log "busy, skipped: $*"; return 0; }
  else
    flock -w 120 9 || { log "lock timeout: $*"; return 1; }
  fi
  "$@"
}

do_pull() {
  local rc=0
  if backoff_active; then log "skip pull: auth backoff"; return 1; fi
  probe_hub || { mark_fail; return 1; }
  pull_state || rc=1
  pull_sessions || rc=1
  if [ $rc = 0 ]; then mark_ok; clear_stale; else mark_fail; fi
  return $rc
}

# shellcheck disable=SC2120
do_push() { # optional explicit session jsonl
  local rc=0
  if backoff_active; then log "skip push: auth backoff"; return 1; fi
  probe_hub || { mark_fail; return 1; }
  push_state || rc=1
  push_sessions "$@" || rc=1
  push_heartbeat
  if [ $rc = 0 ]; then mark_ok; clear_stale; else mark_fail; fi
  return $rc
}

do_sync() {
  local rc=0
  do_pull || rc=1
  # shellcheck disable=SC2119
  do_push || rc=1
  return $rc
}

# --------------------------------------------------------------------- hooks

hook_json() { cat; } # stdin

json_get() { jq -r "$1 // empty" 2>/dev/null <<<"$2" || true; }

conflict_files() {
  find "$CLAUDE_DIR/projects" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/plans" "$CLAUDE_DIR/agents" \
    -name '*.conflict-*' -type f 2>/dev/null | sed "s|^$CLAUDE_DIR/||"
}

hook_start() {
  export CLAUDE_SYNC_AUTO=1
  local input; input=$(hook_json)
  local session_id source transcript
  session_id=$(json_get .session_id "$input")
  source=$(json_get .source "$input")
  transcript=$(json_get .transcript_path "$input")
  # pull synchronously so memory is current before Claude reads it; bounded.
  timeout 45 "$0" pull >/dev/null 2>&1 || true

  local ctx=""
  # foreign session resumed without a fork (picker, IDE, --bare launch...)
  if [ "$source" = resume ] && [ -n "$transcript" ] && [ -f "$transcript" ]; then
    local o; o=$(owner_of "$transcript")
    if [ -n "$o" ] && [ "$o" != "$MACHINE" ]; then
      ctx+="claude-sync WARNING: this session ($session_id) belongs to $o and was resumed on $MACHINE without --fork-session. Its transcript will NOT be pushed to the hub from here. Tell the user to exit and reopen with: claude --resume $session_id --fork-session (the claude wrapper does this automatically for -r <id> and -c)."$'\n'
      notify "foreign session" "$session_id belongs to $o. Reopen with --fork-session to keep it synced."
    fi
  fi
  local conflicts; conflicts=$(conflict_files)
  if [ -n "$conflicts" ]; then
    ctx+="claude-sync: memory conflicts pending. For each pair below, merge the .conflict-<machine> file into the base file (keep every fact, newest wins on contradictions), delete the .conflict file, and update MEMORY.md if needed:"$'\n'"$conflicts"$'\n'
  fi
  [ -n "$ctx" ] && printf '%s' "$ctx"
  return 0
}

hook_stop() {
  export CLAUDE_SYNC_AUTO=1
  local input; input=$(hook_json)
  local transcript; transcript=$(json_get .transcript_path "$input")
  # Background: Stop hooks may take long but the user is waiting for the prompt.
  setsid -f "$0" bg-push "$transcript" >/dev/null 2>&1 </dev/null || true
  return 0
}

hook_end() {
  # SessionEnd has a 1.5 s total budget: only fork and return.
  export CLAUDE_SYNC_AUTO=1
  local input; input=$(hook_json)
  local transcript cwd; transcript=$(json_get .transcript_path "$input"); cwd=$(json_get .cwd "$input")
  setsid -f "$0" bg-end "$transcript" "$cwd" >/dev/null 2>&1 </dev/null || true
  return 0
}

bg_push() { # $1 = transcript path (may be empty)
  if [ -n "${1:-}" ] && [ -f "$1" ]; then
    with_lock -n do_push "$1"
  else
    with_lock -n do_push
  fi
}

bg_end() { # $1 transcript, $2 cwd
  with_lock -w do_push "${1:-}" || true
  local cwd=${2:-}
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  [ "$(readlink -f "$cwd")" = "$(readlink -f "$CLAUDE_DIR")" ] && return 0
  git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local top; top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 0
  local dirty ahead=0
  dirty=$(git -C "$top" status --porcelain 2>/dev/null | wc -l)
  if git -C "$top" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    ahead=$(git -C "$top" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)
  fi
  if [ "$dirty" -gt 0 ] || [ "$ahead" -gt 0 ]; then
    notify "unpushed work in $(basename "$top")" "$dirty uncommitted file(s), $ahead unpushed commit(s). The session is synced, the code is not."
  fi
}

# ------------------------------------------------------------------ wrapper

project_key() { # cwd → ~/.claude/projects/<key>
  local k=$1
  printf '%s' "${k//[^A-Za-z0-9]/-}"
}

latest_session_here() {
  local key; key=$(project_key "$PWD")
  local dir="$CLAUDE_DIR/projects/$key"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

session_by_id() { # $1 uuid → path or empty
  find "$CLAUDE_DIR/projects" -mindepth 2 -maxdepth 2 -name "$1.jsonl" 2>/dev/null | head -1
}

wrap() {
  local -a args=("$@")
  local skip_pull=0 want_fork=0 has_fork=0 target=""
  case "${1:-}" in
    --version|-v|--help|-h|mcp|plugin|config|doctor|update|install|agents|attach|logs|stop|kill|rm|setup-token|ultrareview|auth|login|logout) skip_pull=1 ;;
  esac
  local i
  for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
      --fork-session) has_fork=1 ;;
      -c|--continue) target=latest ;;
      -r|--resume)
        local nxt="${args[i+1]:-}"
        if [[ "$nxt" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then target="$nxt"; fi ;;
      --resume=*) target="${args[i]#--resume=}" ;;
    esac
  done
  if [ $skip_pull = 0 ]; then
    CLAUDE_SYNC_AUTO=1 timeout 45 "$0" pull >/dev/null 2>&1 || true
  fi
  if [ $has_fork = 0 ] && [ -n "$target" ]; then
    local path=""
    if [ "$target" = latest ]; then path=$(latest_session_here); else path=$(session_by_id "$target"); fi
    if [ -n "$path" ] && ! owned_here "$path"; then
      want_fork=1
      echo "claude-sync: session $(basename "$path" .jsonl) belongs to $(owner_of "$path") → forking on $MACHINE" >&2
      log "wrapper: forking foreign session $(basename "$path" .jsonl)"
    fi
  fi
  if [ $want_fork = 1 ]; then
    unset GIT_SSH_COMMAND # hub key + port 56777 must not leak into Claude's own git pushes
    exec "$REAL_CLAUDE" "${args[@]}" --fork-session
  fi
  unset GIT_SSH_COMMAND # hub key + port 56777 must not leak into Claude's own git pushes
  exec "$REAL_CLAUDE" "${args[@]}"
}

# --------------------------------------------------------------------- misc

ensure_key() {
  if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "claude-sync@$MACHINE" -f "$KEY"
    chmod 600 "$KEY"
    log "generated hub key $KEY"
  fi
}

cmd_init() {
  ensure_key
  ensure_repo
  commit_local
  echo "claude-sync init on $MACHINE"
  echo "  public key: $(cat "$KEY.pub")"
  if ! hub_reachable; then
    echo "  hub $HUB_HOST not reachable with this key yet."
    echo "  Add the public key to claudeSyncHubKeys in the VPS profile, deploy, then run: claude-sync sync"
    return 1
  fi
  if with_lock -w do_sync; then echo "  synced with hub."; else echo "  sync had errors, see $LOG"; return 1; fi
}

cmd_status() {
  echo "machine:   $MACHINE"
  echo "hub:       $HUB:$HUB_PORT/$HUB_DIR"
  echo "key:       $KEY $([ -f "$KEY" ] && echo present || echo MISSING)"
  if hub_reachable; then echo "reachable: yes"; else echo "reachable: NO"; fi
  local ok; ok=$(cat "$STATE_DIR/last-ok" 2>/dev/null || echo 0)
  if [ "$ok" != 0 ]; then echo "last ok:   $(date -d "@$ok" '+%F %T')"; else echo "last ok:   never"; fi
  [ -f "$STATE_DIR/first-fail" ] && echo "failing since: $(date -d "@$(cat "$STATE_DIR/first-fail")" '+%F %T')"
  if [ -d "$CLAUDE_DIR/.git" ]; then
    echo "state:     $(git_state rev-parse --short HEAD 2>/dev/null || echo '-') ($(git_state log --oneline 2>/dev/null | wc -l) commits)"
    local dirty; dirty=$(git_state status --porcelain 2>/dev/null | wc -l)
    echo "uncommitted: $dirty file(s)"
    if git_state rev-parse --verify hub/main >/dev/null 2>&1; then
      echo "ahead/behind hub: $(git_state rev-list --count hub/main..HEAD 2>/dev/null)/$(git_state rev-list --count HEAD..hub/main 2>/dev/null)"
    fi
  else
    echo "state:     no repo (run claude-sync init)"
  fi
  local c; c=$(conflict_files)
  if [ -n "$c" ]; then echo "CONFLICTS pending:"; printf '  %s\n' "$c"; else echo "conflicts: none"; fi
  echo "owned sessions (last $PUSH_WINDOW_DAYS d):"
  find "$CLAUDE_DIR/projects" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime "-$PUSH_WINDOW_DAYS" 2>/dev/null | while read -r j; do
    echo "  $(basename "$j" .jsonl) owner=$(owner_of "$j" || true) $(du -h "$j" | cut -f1)"
  done
  echo "log:       $LOG"
}

cmd=${1:-help}; shift || true
case "$cmd" in
  init)       cmd_init ;;
  sync)       with_lock -w do_sync ;;
  pull)       with_lock -w do_pull ;;
  push)       with_lock -w do_push "$@" ;;
  status)     cmd_status ;;
  pubkey)     ensure_key; cat "$KEY.pub" ;;
  hook-start) hook_start ;;
  hook-stop)  hook_stop ;;
  hook-end)   hook_end ;;
  bg-push)    bg_push "$@" ;;
  bg-end)     bg_end "$@" ;;
  wrap)       wrap "$@" ;;
  help|*)
    cat <<'EOH'
claude-sync — keep ~/.claude in step across machines through the VPS hub
  init      first run on a machine: key, repo, merge with hub, push
  sync      commit + pull + push both channels (what the timer runs)
  pull      hub → here (memory/config git merge, sessions additive)
  push      here → hub (owned sessions only)
  status    hub reachability, pending conflicts, owned sessions
  pubkey    print this machine's hub public key
  hook-start | hook-stop | hook-end   Claude Code hooks (stdin JSON)
  wrap ARGS...   the `claude` wrapper: pull, fork foreign sessions, exec
EOH
    ;;
esac
