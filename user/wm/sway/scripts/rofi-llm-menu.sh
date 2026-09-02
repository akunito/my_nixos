#!/usr/bin/env bash
set -uo pipefail

# Rofi script-mode: pick and control the local LLM.
# - No args: print the menu.
# - One arg (the chosen row): act on it, using $ROFI_INFO for the payload.
#
# THE LIST IS BUILT AT RUNTIME from /api/tags, never from the Nix config, so a
# model added to ollamaServerCustomModels + `ollama-pull` shows up here with no
# change to waybar, this script, or anything else.
#
# `hf.co/...` rows are filtered out on purpose: those are the GGUF blobs that
# `ollama create` used as FROM sources. They are real, loadable models, but
# picking one bypasses the Modelfile — losing num_ctx and the sampling profile —
# so offering them would be offering a worse copy of the row above.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

PORT="${LLM_PORT:-8090}"
API="http://127.0.0.1:${PORT}"
LOCK="/run/llama-gaming/lock"
# Waybar refreshes on this signal instead of waiting out its poll interval, so
# the bar reflects an action the moment it lands. Must match `signal` in waybar.nix.
WAYBAR_SIGNAL=6

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send -a "Local LLM" "$1" "${2:-}" || true
}
refresh_bar() { pkill -RTMIN+${WAYBAR_SIGNAL} waybar 2>/dev/null || true; }

# NO `icon` field, deliberately. The labels already carry a glyph, and rofi's
# themed icon would render NEXT to it — every row came out with two symbols
# ("◉○ gpt-oss:20b"). The text markers win because they also carry state: ● is
# the resident model, ○ is not.
row() { # label, info-payload
  printf '%s\0info\x1f%s\n' "$1" "$2"
}

# ---------------------------------------------------------------- menu -------
if [ "$#" -eq 0 ]; then
  # Header line: rofi shows this as the prompt/message, cheap situational awareness.
  free_mib=0
  for d in /sys/class/drm/card*/device; do
    t=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
    u=$(cat "$d/mem_info_vram_used" 2>/dev/null || echo 0)
    [ "$t" -gt 0 ] && free_mib=$(( (t - u) / 1048576 ))
  done
  if [ -e "$LOCK" ]; then
    printf '\0message\x1fLOCKED — nothing will load · %s MiB free\n' "$free_mib"
  else
    printf '\0message\x1f%s MiB VRAM free\n' "$free_mib"
  fi

  loaded="$(curl -sf --max-time 2 "${API}/api/ps" 2>/dev/null \
            | python3 -c 'import json,sys;m=(json.load(sys.stdin).get("models") or [{}])[0];print(m.get("name",""))' 2>/dev/null || echo '')"

  # The JSON goes in as an ARGUMENT, not on stdin: the heredoc below already owns
  # stdin, so piping curl into python here silently yields an empty list.
  tags="$(curl -sf --max-time 3 "${API}/api/tags" 2>/dev/null || echo '')"
  python3 - "$loaded" "$tags" <<'PY'
import json, sys
loaded = sys.argv[1]
try:
    models = json.loads(sys.argv[2] or '{}').get("models") or []
except Exception:
    models = []
for m in sorted(models, key=lambda x: x["name"]):
    name = m["name"]
    if name.startswith("hf.co/"):      # see the header note
        continue
    short = name.removesuffix(":latest")
    if name == loaded:
        label = f"● {short}   resident"
    else:
        label = f"○ {short}   {m['size']/1e9:.1f} GB"
    print(f"{label}\0info\x1fload:{name}")
PY

  if [ -e "$LOCK" ]; then
    row "󰍁  Unlock — allow models to load again" "unlock"
  else
    row "󰍁  Lock — free VRAM and block loading" "lock"
  fi
  row "󰅖  Unload the resident model" "unload"
  row "󰃢  llama-evict — reclaim cold buffers" "evict"
  exit 0
fi

# -------------------------------------------------------------- actions ------
action="${ROFI_INFO:-}"

case "$action" in
  lock)
    llama-lock >/dev/null 2>&1
    notify "Locked" "Models will not load; VRAM freed."
    ;;
  unlock)
    llama-unlock >/dev/null 2>&1
    notify "Unlocked" "The next request will load a model again."
    ;;
  unload)
    curl -sf --max-time 5 "${API}/api/generate" \
      -d '{"model":"'"$(curl -sf --max-time 2 "${API}/api/ps" | python3 -c 'import json,sys;m=(json.load(sys.stdin).get("models") or [{}])[0];print(m.get("name",""))')"'","keep_alive":0}' \
      >/dev/null 2>&1
    notify "Unloaded" "VRAM released."
    ;;
  evict)
    # Documented as livelock-prone on a busy desktop, so it is NEVER run
    # automatically — only from here, where a human just asked for it.
    notify "llama-evict" "Reclaiming cold buffers… this can take a while."
    ( llama-evict >/dev/null 2>&1; refresh_bar ) &
    ;;
  load:*)
    model="${action#load:}"
    if [ -e "$LOCK" ]; then
      notify "Locked" "Unlock first — a game may be running."
      exit 0
    fi
    # A cold load of a 13 GB model takes tens of seconds. Background it so rofi
    # closes immediately, and refresh the bar when it finishes.
    notify "Loading ${model%%:latest}" "Cold start; the bar will update when it is resident."
    ( curl -sf --max-time 600 "${API}/api/generate" -d '{"model":"'"$model"'","prompt":""}' >/dev/null 2>&1
      refresh_bar ) &
    ;;
esac

refresh_bar
