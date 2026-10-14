#!/usr/bin/env bash
# Rofi script-mode: pick the NAS 3090 preset (system/app/ai-presets.nix).
# - No args: print the menu, built from the NAS status endpoint (presets are
#   defined in Nix on the NAS; nothing here needs to change when one is added).
# - One arg (the chosen row): switch, via ssh + a sudo rule narrowed to
#   `ai preset set` on the NAS, then refresh the Waybar module (signal 7).
set -uo pipefail
PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"
URL="${NAS_AI_URL:-http://100.64.0.1:8093/status}"
GATE="${NAS_AI_GATE:-http://100.64.0.1:8090}"
NAS="${NAS_AI_SSH:-akunito@100.64.0.1}"

if [ $# -eq 0 ]; then
    printf '\0prompt\x1fNAS 3090\n'
    if ! j=$(curl -fsS --max-time 2 "$URL" 2>/dev/null); then
        printf 'NAS asleep or down (23:00-16:00) — nothing to switch\0nonselectable\x1ftrue\n'
        exit 0
    fi
    # "Stop" goes straight to the gate over HTTP (no ssh, no sudo, no agent key):
    # cuts every in-flight request and keeps the model. Switching/off still
    # go through ssh + `ai preset set`, which cuts in-flight requests itself.
    printf '⏹ Stop — cut what is running now (model stays loaded)\0info\x1fstop\n'
    jq -r '
      .preset as $cur
      | .presets[]
      | "\(if .id == $cur then "★ " else "   " end)\(.label)   \(.vram_est // "")\u0000info\u001f\(.id)"
    ' <<<"$j"
    exit 0
fi

id="${ROFI_INFO:-}"
[ -n "$id" ] || exit 0
if [ "$id" = "stop" ]; then
    if out=$(curl -fsS --max-time 5 -X POST "$GATE/gate/abort" 2>&1); then
        notify-send -t 4000 "NAS 3090" "stopped: $out" >/dev/null 2>&1 || true
    else
        notify-send -u critical -t 8000 "NAS 3090" "stop failed: ${out:0:300}" >/dev/null 2>&1 || true
    fi
    pkill -RTMIN+7 -x '\.?waybar(-wrapped)?' 2>/dev/null || true
    exit 0
fi
export SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null)}"
if out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$NAS" "sudo -n /run/current-system/sw/bin/ai preset set $(printf '%q' "$id")" 2>&1); then
    notify-send -t 4000 "NAS 3090" "preset → $id" >/dev/null 2>&1 || true
else
    notify-send -u critical -t 8000 "NAS 3090" "switch to $id failed: ${out:0:300}" >/dev/null 2>&1 || true
fi
pkill -RTMIN+7 -x '\.?waybar(-wrapped)?' 2>/dev/null || true
exit 0
