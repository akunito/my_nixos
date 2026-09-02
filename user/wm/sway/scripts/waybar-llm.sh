#!/usr/bin/env bash
set -uo pipefail

# Waybar status for the local LLM (Ollama on this host).
#
# Prints one line of JSON: {"text":..,"tooltip":..,"class":..}
#
# WHY A DEDICATED MODULE when custom/vram already shows card usage: VRAM tells
# you the card is full, not WHY, and the number that actually decides whether
# the model is fast is `size_vram / size` from /api/ps — the share of the model
# that really landed on the GPU. Measured 2026-09-02, the same model went 36 ->
# 21 -> 14 tok/s as that share fell from 100% to 95% to 89%, purely because the
# desktop grew. That share is invisible everywhere else, so it is the headline
# here and the reason the module exists.
#
# States, in the order they are checked (each one hides the ones below it):
#   down    ollama is not running at all
#   locked  the gaming lock is held — no model can load (see ollama-server.nix)
#   idle    service up, nothing resident
#   spill   a model is resident but part of it is in system RAM  <- the warning
#   ok      a model is resident, entirely on the GPU
#
# Deliberately does NOT start anything. Waybar polls this every few seconds; a
# module that could trigger a 13 GB model load on a timer would be a trap.

PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:$PATH"

PORT="${LLM_PORT:-8090}"
API="http://127.0.0.1:${PORT}"
LOCK="/run/llama-gaming/lock"

emit() { # text, tooltip, class
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
print(json.dumps({"text": sys.argv[1], "tooltip": sys.argv[2], "class": sys.argv[3]}))
PY
}

# Free VRAM on the biggest card, from sysfs — the same source llama-status and
# custom/vram read, so the three can never disagree.
vram_free_mib() {
  local best=0 used=0 t u
  for d in /sys/class/drm/card*/device; do
    t=$(cat "$d/mem_info_vram_total" 2>/dev/null || echo 0)
    if [ "$t" -gt "$best" ]; then
      best=$t
      u=$(cat "$d/mem_info_vram_used" 2>/dev/null || echo 0)
      used=$u
    fi
  done
  [ "$best" -gt 0 ] && echo $(( (best - used) / 1048576 )) || echo 0
}

FREE="$(vram_free_mib)"

if [ -e "$LOCK" ]; then
  emit "󰍁 locked" "Local LLM locked — a game is running, or llama-lock was run.
No model will load. ${FREE} MiB free.

Click for the model menu." "locked"
  exit 0
fi

if ! systemctl is-active --quiet ollama 2>/dev/null; then
  emit "󰅗 down" "ollama is not running.
${FREE} MiB VRAM free.

Click for the model menu." "down"
  exit 0
fi

PS="$(curl -sf --max-time 2 "${API}/api/ps" 2>/dev/null || echo '')"
[ -n "$PS" ] || { emit "󰅗 down" "ollama is not answering on ${API}." "down"; exit 0; }

python3 - "$PS" "$FREE" <<'PY'
import json, sys, datetime

ps = json.loads(sys.argv[1] or '{"models":[]}')
free = int(sys.argv[2])
models = ps.get("models") or []

def out(text, tooltip, cls):
    print(json.dumps({"text": text, "tooltip": tooltip, "class": cls}))

if not models:
    out("󰚩 idle",
        f"No model resident.\n{free} MiB VRAM free.\n\nClick for the model menu.",
        "idle")
    raise SystemExit

m = models[0]
# Strip the ":latest" Ollama appends; it is noise in a 30-pixel slot.
name = m["name"].removesuffix(":latest")
total, vram = m.get("size", 0), m.get("size_vram", 0)
pct = round(100 * vram / total) if total else 0

# Minutes until OLLAMA_KEEP_ALIVE unloads it. Best-effort: the timestamp carries
# an offset and a variable number of fractional digits, so a parse failure just
# drops the line rather than breaking the module.
when = ""
try:
    exp = m.get("expires_at", "")
    if exp:
        head, _, tail = exp.partition(".")
        tz = tail[-6:] if len(tail) >= 6 and tail[-6] in "+-" else ""
        dt = datetime.datetime.fromisoformat(head + tz)
        mins = round((dt - datetime.datetime.now(dt.tzinfo)).total_seconds() / 60)
        if mins > 0:
            when = f" · unloads in {mins} min"
except Exception:
    pass

gib = total / 2**30
if pct >= 100:
    out(f"󰚩 {name} 100%",
        f"{name}\n{gib:.1f} GiB · fully on GPU{when}\n{free} MiB VRAM free.\n\nClick for the model menu.",
        "ok")
else:
    spilled = (total - vram) / 2**20
    out(f"󰚩 {name} {pct}%",
        f"{name}\n{gib:.1f} GiB · only {pct}% on GPU, {spilled:.0f} MiB in system RAM{when}\n"
        f"Decode is much slower like this — close something or pick a smaller quant.\n"
        f"{free} MiB VRAM free.\n\nClick for the model menu.",
        "spill")
PY
