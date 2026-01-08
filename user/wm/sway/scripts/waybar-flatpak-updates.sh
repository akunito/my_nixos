#!/usr/bin/env bash
set -euo pipefail

# Usage: waybar-flatpak-updates.sh [/nix/store/.../bin/flatpak]
FLATPAK_BIN="${1:-flatpak}"

icon="󰏓"

if ! command -v "$FLATPAK_BIN" >/dev/null 2>&1; then
  # fall back to plain `flatpak` if a path was provided but isn't executable
  FLATPAK_BIN="flatpak"
fi

if ! command -v "$FLATPAK_BIN" >/dev/null 2>&1; then
  printf '{"text":"","tooltip":"flatpak not found","class":"hidden"}\n'
  exit 0
fi

# Read-only listing of available updates.
# `remote-ls --updates` does not perform installation, it reads remote metadata.
updates="$("$FLATPAK_BIN" remote-ls --updates --columns=application 2>/dev/null || true)"

count=0
if [[ -n "$updates" ]]; then
  # Count non-empty lines (no awk; Waybar/systemd PATH can be minimal)
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] || continue
    count=$((count + 1))
  done <<<"$updates"
fi

if [[ "$count" == "0" ]]; then
  printf '{"text":"","tooltip":"No Flatpak updates","class":"hidden"}\n'
  exit 0
fi

text="${icon} ${count}"
tooltip="Flatpak updates: ${count}\n\n${updates}"

# Minimal JSON escaping (quotes + backslashes + newlines)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

printf '{"text":"%s","tooltip":"%s","class":"updates"}\n' "$(json_escape "$text")" "$(json_escape "$tooltip")"


