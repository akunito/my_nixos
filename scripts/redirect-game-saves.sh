#!/usr/bin/env bash

# redirect-game-saves.sh — Route a wine prefix's save dirs through ~/GameSaves/
#
# Usage:
#   scripts/redirect-game-saves.sh <prefix-path>            # dry run (default)
#   scripts/redirect-game-saves.sh <prefix-path> --execute  # apply changes
#
# What it does:
#   For AppData/LocalLow, AppData/Roaming, and Documents in the given prefix,
#   merge existing content into ~/GameSaves/{LocalLow,Roaming,Documents} and
#   replace the original directory with a symlink to that shared location.
#
#   This makes saves:
#     - shared across every prefix that's been routed this way
#     - backed up automatically (GameSaves/ is under $HOME, not in HOME_EXCLUDES)
#     - resilient to prefix deletion / recreation
#
# Skipped on purpose:
#   - AppData/Local  (caches, launcher state — cross-prefix sharing breaks things)

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=1
PREFIX=""

for arg in "$@"; do
  case "$arg" in
    --execute) DRY_RUN=0 ;;
    --help|-h)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      echo "Unknown flag: $arg" >&2
      exit 2 ;;
    *)
      if [ -z "$PREFIX" ]; then PREFIX="$arg"; else echo "Too many args" >&2; exit 2; fi ;;
  esac
done

if [ -z "$PREFIX" ]; then
  echo "Usage: $SCRIPT_NAME <prefix-path> [--execute]" >&2
  exit 2
fi

if [ ! -d "$PREFIX" ]; then
  echo "[ERROR] Prefix not found: $PREFIX" >&2
  exit 1
fi

USERS_DIR="$PREFIX/drive_c/users"
if [ ! -d "$USERS_DIR" ]; then
  echo "[ERROR] Not a wine prefix (no drive_c/users): $PREFIX" >&2
  exit 1
fi

WIN_USER=""
for candidate in steamuser "$USER"; do
  if [ -d "$USERS_DIR/$candidate" ]; then
    WIN_USER="$candidate"
    break
  fi
done
if [ -z "$WIN_USER" ]; then
  WIN_USER="$(ls -1 "$USERS_DIR" 2>/dev/null | grep -v '^Public$' | head -1 || true)"
fi
if [ -z "$WIN_USER" ] || [ ! -d "$USERS_DIR/$WIN_USER" ]; then
  echo "[ERROR] Could not find a windows user dir under $USERS_DIR" >&2
  exit 1
fi

USER_HOME="$USERS_DIR/$WIN_USER"
GAMESAVES="$HOME/GameSaves"

info()  { echo "[INFO] $*"; }
warn()  { echo "[WARN] $*" >&2; }

# Run a command. In dry-run mode, just print it.
do_run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '       '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# True if $1 is a directory containing no regular files (empty or only empty subdirs)
is_empty_tree() {
  local d="$1"
  [ -d "$d" ] && [ -z "$(find "$d" -mindepth 1 \( -type f -o -type l \) -print -quit 2>/dev/null)" ]
}

info "Prefix:       $PREFIX"
info "Windows user: $WIN_USER"
info "GameSaves:    $GAMESAVES"
if [ "$DRY_RUN" -eq 1 ]; then
  info "Mode: DRY RUN (no changes). Pass --execute to apply."
else
  info "Mode: EXECUTE"
fi
echo

do_run mkdir -p "$GAMESAVES/LocalLow" "$GAMESAVES/Roaming" "$GAMESAVES/Documents"

# process_path <prefix-relative-src-dir> <gamesaves-subdir-name>
process_path() {
  local rel="$1"
  local bucket="$2"
  local src="$USER_HOME/$rel"
  local dst="$GAMESAVES/$bucket"

  echo "--- $rel -> GameSaves/$bucket ---"

  # Already a correctly-pointing symlink?
  if [ -L "$src" ]; then
    local target
    target="$(readlink -f "$src" 2>/dev/null || true)"
    if [ "$target" = "$(readlink -f "$dst" 2>/dev/null || echo "$dst")" ]; then
      info "Already linked correctly; skipping."
      return 0
    else
      warn "Existing symlink points elsewhere: $src -> $target"
      warn "Refusing to touch it. Remove it manually and re-run."
      return 0
    fi
  fi

  # Source missing — create symlink directly
  if [ ! -d "$src" ]; then
    info "Source dir absent; creating symlink directly."
    do_run mkdir -p "$(dirname "$src")"
    do_run ln -s "$dst" "$src"
    return 0
  fi

  do_run mkdir -p "$dst"

  local moved=0
  local conflicts=0
  local pruned=0

  # Use a glob expanded into a temp variable to preserve spaces, etc.
  shopt -s nullglob dotglob
  local children=( "$src"/* )
  shopt -u nullglob dotglob

  local child
  for child in "${children[@]}"; do
    local name
    name="$(basename "$child")"
    if [ -e "$dst/$name" ] || [ -L "$dst/$name" ]; then
      # If both sides have empty trees, silently drop the source (wine placeholder dirs like Downloads/Music/Pictures/...)
      if is_empty_tree "$child" && { [ -L "$dst/$name" ] || is_empty_tree "$dst/$name"; }; then
        do_run rm -rf -- "$child"
        pruned=$((pruned+1))
        continue
      fi
      warn "CONFLICT: $dst/$name already exists with content; leaving $child in place."
      conflicts=$((conflicts+1))
      continue
    fi
    do_run mv -- "$child" "$dst/"
    moved=$((moved+1))
  done

  info "Moved $moved | pruned-empty $pruned | conflicts $conflicts"

  # If nothing is left, replace src with a symlink
  local remaining=0
  if [ -d "$src" ]; then
    shopt -s nullglob dotglob
    local rest=( "$src"/* )
    shopt -u nullglob dotglob
    remaining=${#rest[@]}
  fi

  if [ "$remaining" -eq 0 ]; then
    do_run rmdir -- "$src"
    do_run ln -s "$dst" "$src"
    info "Linked: $src -> $dst"
  else
    warn "Not symlinking $src — $remaining item(s) remain. Resolve manually and re-run."
  fi
}

process_path "AppData/LocalLow"  "LocalLow"
echo
process_path "AppData/Roaming"   "Roaming"
echo
process_path "Documents"         "Documents"

echo
if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run complete. Re-run with --execute to apply."
else
  info "Done."
fi
