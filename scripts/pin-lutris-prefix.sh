#!/usr/bin/env bash

# pin-lutris-prefix.sh — Audit Lutris game ymls and add missing `game.prefix`.
#
# Why: without an explicit `game.prefix`, Lutris/umu fall back to a default path
# that can silently change across updates (cf. 2026-04-20 incident where
# ~/Games/none was replaced by ~/Games/umu/umu-default, making saves invisible).
#
# Usage:
#   scripts/pin-lutris-prefix.sh                 # audit (dry-run; list missing)
#   scripts/pin-lutris-prefix.sh --fix           # add prefix: ~/Games/<slug>
#                                                # for every yml missing it
#
# The script only touches `game.prefix`. It does NOT set `arch` or `wine.version` —
# the user's working configs don't use those fields. For each yml, the slug is
# derived from the filename (everything before the trailing -<timestamp>.yml).

set -euo pipefail

LUTRIS_GAMES_DIR="$HOME/.local/share/lutris/games"
GAMES_ROOT="$HOME/Games"
FIX=0

for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    --help|-h) sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [ ! -d "$LUTRIS_GAMES_DIR" ]; then
  echo "[ERROR] $LUTRIS_GAMES_DIR not found" >&2
  exit 1
fi

missing=0
fixed=0
ok=0

for yml in "$LUTRIS_GAMES_DIR"/*.yml; do
  [ -f "$yml" ] || continue
  name="$(basename "$yml" .yml)"
  # Strip trailing -<digits> timestamp to get the slug
  slug="${name%-*}"

  if grep -qE '^\s{2,}prefix:' "$yml"; then
    ok=$((ok+1))
    continue
  fi

  missing=$((missing+1))
  target="$GAMES_ROOT/$slug"
  echo "[MISS] $name  (suggest prefix: $target)"

  if [ "$FIX" -eq 1 ]; then
    # Insert `  prefix: <path>` as the 2nd line inside `game:` block.
    # Use awk to insert after the `game:` line only once.
    tmp="$(mktemp)"
    awk -v p="  prefix: $target" '
      BEGIN { inserted=0 }
      /^game:[[:space:]]*$/ && !inserted { print; print p; inserted=1; next }
      { print }
    ' "$yml" > "$tmp"

    # Sanity: make sure the new file still starts with `game:`
    if head -1 "$tmp" | grep -q '^game:'; then
      mv "$tmp" "$yml"
      fixed=$((fixed+1))
      echo "       -> patched"
    else
      rm -f "$tmp"
      echo "[ERROR] Could not patch $yml (unexpected format)" >&2
    fi
  fi
done

echo
echo "Summary: ok=$ok missing=$missing fixed=$fixed"

if [ "$FIX" -eq 0 ] && [ "$missing" -gt 0 ]; then
  echo "Run again with --fix to add the suggested prefixes."
fi
