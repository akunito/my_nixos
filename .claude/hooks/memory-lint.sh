#!/usr/bin/env bash
# memory-lint.sh — SessionStart hook and the backend of /memory-lint.
# Silent when the project's Claude memory is healthy; otherwise prints MEMORY-LINT WARN lines
# that land in Claude's context so the session fixes them. Always exits 0 (non-blocking).
# Usage: <stdin hook JSON> | --cwd DIR | --dir MEMDIR | --all   [--verbose]
# Caps: Claude Code loads only the first 200 lines / 25 KB of MEMORY.md (code.claude.com/docs/en/memory);
# we warn earlier so a session never silently loses index lines (happened 2026-10-06: 93 of 264 lines cut).
set -u
MAX_INDEX_LINES=180; MAX_INDEX_BYTES=22000; MAX_FILE_BYTES=8192; MAX_SUBINDEX_BYTES=20000
PROJECTS="$HOME/.claude/projects"
VERBOSE=0; MODE=hook; ARG=""
while [ $# -gt 0 ]; do case "$1" in
  --verbose) VERBOSE=1;; --all) MODE=all;; --cwd) MODE=cwd; ARG="$2"; shift;; --dir) MODE=dir; ARG="$2"; shift;;
esac; shift; done
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
WARN=0
warn() { WARN=$((WARN+1)); echo "MEMORY-LINT WARN: $*"; }
info() { [ "$VERBOSE" = 1 ] && echo "MEMORY-LINT: $*"; return 0; }

lint_dir() {
  local M="$1" f idx n b
  [ -f "$M/MEMORY.md" ] || { info "$M: no MEMORY.md, nothing to lint"; return 0; }
  local label="${M#$PROJECTS/}"; label="${label%/memory}"
  n=$(wc -l < "$M/MEMORY.md"); b=$(wc -c < "$M/MEMORY.md")
  info "$label: MEMORY.md $n lines, $b bytes"
  [ "$n" -gt "$MAX_INDEX_LINES" ] && warn "$label: MEMORY.md has $n lines (cap $MAX_INDEX_LINES; Claude Code truncates at 200) — move a domain into index_<domain>.md"
  [ "$b" -gt "$MAX_INDEX_BYTES" ] && warn "$label: MEMORY.md is $b bytes (cap $MAX_INDEX_BYTES; Claude Code truncates at 25 KB) — shorten lines or split into index_<domain>.md"
  idx=$(cat "$M/MEMORY.md" "$M"/index_*.md 2>/dev/null)
  for f in "$M"/*.md; do
    [ -e "$f" ] || continue
    local base; base=$(basename "$f")
    case "$base" in MEMORY.md) continue;; esac
    b=$(wc -c < "$f")
    case "$base" in
      index_*) [ "$b" -gt "$MAX_SUBINDEX_BYTES" ] && warn "$label: $base is $b bytes — split the domain"; continue;;
    esac
    [ "$b" -gt "$MAX_FILE_BYTES" ] && warn "$label: $base is $b bytes (cap $MAX_FILE_BYTES) — keep the live facts (<= 1.5 KB), move the log to the repo docs or archive/"
    printf '%s' "$idx" | grep -q -F "($base)" || printf '%s' "$idx" | grep -q -F "[[${base%.md}]]" || warn "$label: $base is not listed in MEMORY.md or any index_*.md — add a one-line entry or delete it"
  done
  # dead links from the indexes
  printf '%s' "$idx" | grep -o -E '\]\([A-Za-z0-9_.-]+\.md\)' | tr -d '()]' | sort -u | while read -r t; do
    [ -f "$M/$t" ] || warn "$label: index links to missing $t"
  done
  # project memories written into the wrong directory (registry = reference_project_locations.md, last table column)
  local reg="$M/reference_project_locations.md"
  if [ -f "$reg" ]; then
    awk -F'|' '/^\| [^|]+ \| `/ && NF>=7 { gsub(/^[ `]+|[ `]+$/,"",$2); gsub(/^[ `]+|[ `]+$/,"",$4); gsub(/^[ `]+|[ `]+$/,"",$7); gsub(/\\/,"",$7); if ($7!="") print $2 "\t" $4 "\t" $7 }' "$reg" |
    while IFS=$'\t' read -r proj mdir pat; do
      for f in "$M"/*.md; do
        base=$(basename "$f"); case "$base" in MEMORY.md|index_*|reference_project_locations.md) continue;; esac
        printf '%s' "${base%.md}" | grep -q -i -E "$pat" && warn "$label: $base belongs to project '$proj' — move it to $PROJECTS/$mdir/memory/ and index it there"
      done
    done
  fi
  if [ "$VERBOSE" = 1 ]; then
    local dang; dang=$(grep -oh '\[\[[^]|#]*' "$M"/*.md 2>/dev/null | sed 's/\[\[//' | sort -u | while read -r t; do [ -f "$M/$t.md" ] || echo "$t"; done | wc -l)
    info "$label: $dang dangling [[wikilink]] targets (allowed, but worth a look during /memory-lint)"
  fi
}

case "$MODE" in
  all) for d in "$PROJECTS"/*/memory; do [ -d "$d" ] && lint_dir "$d"; done;;
  dir) lint_dir "$ARG";;
  cwd) lint_dir "$PROJECTS/$(slug "$ARG")/memory";;
  hook)
    INPUT=$(cat 2>/dev/null || true)
    CWD=""; command -v jq >/dev/null 2>&1 && CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    [ -z "$CWD" ] && CWD="$PWD"
    lint_dir "$PROJECTS/$(slug "$CWD")/memory";;
esac
[ "$WARN" -gt 0 ] && echo "MEMORY-LINT: $WARN warning(s). Fix them this session per the Memory section of ~/.claude/CLAUDE.md, or run /memory-lint for the full audit."
exit 0
