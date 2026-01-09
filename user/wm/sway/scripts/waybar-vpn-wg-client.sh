#!/usr/bin/env bash
set -euo pipefail

# Waybar VPN status module for wg-client
# Usage: waybar-vpn-wg-client.sh /nix/store/.../bin/ip

IP_BIN="${1:-ip}"
IFACE="wg-client"

if ! command -v "$IP_BIN" >/dev/null 2>&1; then
  IP_BIN="ip"
fi

icon=""
dot=""

is_on=false
if command -v "$IP_BIN" >/dev/null 2>&1; then
  if "$IP_BIN" link show "$IFACE" >/dev/null 2>&1; then
    is_on=true
  fi
fi

if [[ "$is_on" == "true" ]]; then
  text="${icon} ${dot}"
  cls="on"
  tip="VPN: ON\n\nClick: toggle (down)"
else
  text="${icon}"
  cls="off"
  tip="VPN: OFF\n\nClick: toggle (up)"
fi

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(json_escape "$text")" "$(json_escape "$tip")" "$cls"


