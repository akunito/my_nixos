#!/usr/bin/env bash
set -euo pipefail

# Waybar NixOS update button
# Shows a NixOS icon; click runs install.sh (wired in waybar.nix).

icon=""
tooltip="Update NixOS (run install.sh)"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

printf '{"text":"%s","tooltip":"%s","class":"nixos-update"}\n' \
  "$(json_escape "$icon")" "$(json_escape "$tooltip")"


