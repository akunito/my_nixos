# NAS preset tests (on demand, from DESK)

They switch the 3090 and interrupt whatever is loaded: check `curl -s http://100.64.0.1:8093/status` (GPU util) first, and restore the preset that was loaded at the end (`ssh -A akunito@100.64.0.1 sudo -n /run/current-system/sw/bin/ai preset set <name>`). Ask Diego before switching while he works.

- `measure_presets.sh PRESET…` — switch through the widget path (ssh + `ai preset set`), wait for loaded, VRAM, one 200-token chat (tok/s). Chat presets only.
- `measure_decision.sh PRESET…` — decision models: switch, VRAM, `POST /v1/systemone` with `payloads/text.json` (+ `image.json` for decider/clef). Raw responses in `$OUT` (default /tmp/ai-preset-results).
- `needle_recall.py MODEL FILLER COPIES` — long-context recall (three planted sentences).
- `router_test.sh` — runs ON the NAS as root (`ssh -A … 'sudo bash -s' < router_test.sh`): a throw-away router on :8095 to check eviction under --models-max 1; the NAS has no jq (the script avoids it).

Measured numbers live in `profiles/NAS_PROD-config.nix` (comments next to each preset) and `docs/akunito/plans/nas-3090-ai-presets.md`.
