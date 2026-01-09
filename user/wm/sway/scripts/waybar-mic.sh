#!/usr/bin/env bash
set -euo pipefail

# Waybar microphone widget (default source volume).
# Usage: waybar-mic.sh /nix/store/.../bin/pactl

PACTL_BIN="${1:-pactl}"

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Encode literal newlines as JSON \n so Waybar renders them as new lines.
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

if ! command -v "$PACTL_BIN" >/dev/null 2>&1; then
  printf '{"text":"","tooltip":"pactl not found","class":"hidden"}\n'
  exit 0
fi

mute="$("$PACTL_BIN" get-source-mute @DEFAULT_SOURCE@ 2>/dev/null || echo "Mute: yes")"
vol_line="$("$PACTL_BIN" get-source-volume @DEFAULT_SOURCE@ 2>/dev/null || true)"

# Extract the first percentage we see, e.g. " / 53% / " (pure bash; no external tools)
pct=0
if [[ "$vol_line" =~ ([0-9]+)% ]]; then
  pct="${BASH_REMATCH[1]}"
fi

is_muted="false"
if [[ "$mute" == *"Mute: yes"* ]]; then
  is_muted="true"
fi

if [[ "$is_muted" == "true" ]]; then
  icon="󰍭"
  cls="muted"
else
  icon="󰍬"
  cls="on"
fi

text="${pct}% ${icon}"
tip="Microphone

Volume: ${pct}%
Muted: ${is_muted}

Click: open pavucontrol"

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(json_escape "$text")" "$(json_escape "$tip")" "$cls"


