#!/usr/bin/env bash
# Waybar status for the NAS 3090 preset manager (system/app/ai-presets.nix on
# NAS_PROD). One line of JSON: {"text","tooltip","class"}.
#
# Reads the read-only status endpoint the NAS serves on tailscale0; never
# changes anything (switching is rofi-nas-llm-menu.sh). The NAS sleeps
# 23:00-16:00 (S3) and WoL does not wake it, so "no answer" is a normal state,
# shown as asleep rather than as an error.
#
# Classes: asleep (no answer) | off (no preset) | idle (preset chosen, model not
# loaded yet: the backend is socket-activated) | loading | ok | busy (GPU > 50 %).
set -uo pipefail
PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"
URL="${NAS_AI_URL:-http://100.64.0.1:8093/status}"

if ! j=$(curl -fsS --max-time 1.5 "$URL" 2>/dev/null); then
    jq -cn '{text: "󰒋 NAS zz", tooltip: "NAS AI: no answer (asleep 23:00-16:00, or down)", class: "asleep"}'
    exit 0
fi

jq -c '
  def gb: ((. // 0) / 1024 * 10 | round / 10 | tostring) + "G";
  (.gpu // {}) as $g
  | (.presets // [] | map({(.id): .}) | add // {}) as $p
  | ($p[.preset // ""] // {}) as $cur
  | (if .preset == null or .preset == "off" then "off"
     elif .state == "loading" then "loading"
     elif .state == "loaded" and (($g.util_pct // 0) > 50) then "busy"
     elif .state == "loaded" then "ok"
     else "idle" end) as $cls
  | {
      text: (if $cls == "off" then "󰒋 NAS off"
             else "󰒋 \($cur.short // .preset) · \($g.vram_used_mb | gb) · \($g.temp_c // "?")°" end),
      tooltip: ("NAS 3090 — preset: \(.preset // "off") (\($cur.label // "-"))\n"
                + "state: \(.state // "?")   model: \(.model_alias // "-")   ctx: \(.ctx // "-") × \(.slots // "-") slot(s), KV \(.kv // "-")\n"
                + (if (.kind // "chat") == "decision" then "decision model: answers only POST /v1/systemone (chat → 501)\n" else "" end)
                + "VRAM \($g.vram_used_mb | gb) / \($g.vram_total_mb | gb)   \($g.temp_c // "?")°C   \($g.power_w // "?") W   GPU \($g.util_pct // "?") %\n"
                + "click: switch preset"),
      class: $cls
    }' <<<"$j" 2>/dev/null || jq -cn '{text: "󰒋 NAS ?", tooltip: "NAS AI: unreadable status", class: "asleep"}'
