#!/usr/bin/env bash
# profile-context.sh — SessionStart hook (startup|resume|clear|fork|compact).
# Prints the per-machine rules of ../context/*.md for $ENV_PROFILE into the session context, so a
# rule like "docker is rootless here" reaches EVERY project opened on that machine and no other.
# CLAUDE.md cannot do that (per repo, unconditional) and @import loads eagerly. Stdout is capped at
# 10,000 chars by Claude Code (overflow goes to a file Claude never reads): keep one profile's
# files under ~6 KB. Non-blocking, always exits 0. Test: ENV_PROFILE=DESK_W11 ./profile-context.sh
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../context" 2>/dev/null && pwd)"
P="${ENV_PROFILE:-}"
[ -n "$P" ] && [ -n "$DIR" ] || exit 0
files=()
case "$P" in
  DESK|LAPTOP_X13)         files+=(workstation.md) ;;
  DESK_W11)                files+=(desk-w11.md) ;;
  MACBOOK_KOMI|KOMI_LXC_*) files+=(komi.md) ;;
esac
[ -n "${files[*]:-}" ] || exit 0   # not ${#files[@]}: errors under set -u on macOS bash 3.2
echo "# Machine rules for ENV_PROFILE=$P (~/.dotfiles/.claude/context, injected by profile-context.sh)"
for f in "${files[@]}"; do
  [ -f "$DIR/$f" ] && cat "$DIR/$f"
done
exit 0
