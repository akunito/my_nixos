# OpenClaw Matrix Integration

E2E-encrypted Matrix channels for OpenClaw agents (Alfred, Vaultkeeper, Scout) with Telegram fallback notifications.

## Two Approaches

### Phase A: Native Plugin (PREFERRED)

OpenClaw v2026.2.26 includes a native Matrix channel plugin at `/app/extensions/matrix/` with multi-account support, E2E encryption, and room allowlists. This is configured directly in `openclaw.json`.

**Architecture:**
```
@akunito:akunito.com (Element)
    | E2E encrypted (matrix-bot-sdk + matrix-sdk-crypto-nodejs)
Matrix Synapse (:8008)
    |
OpenClaw Gateway (:18789) — native Matrix channel plugin
  |-- 3 accounts (alfred, vaultkeeper, scout)
  |-- Each account = separate bot user + crypto store
  |-- Bindings route rooms -> agents
```

**Configuration**: See `openclaw.json.template` — `channels.matrix` section with `accounts` map.

### Phase B: External Bridge (FALLBACK)

If the native plugin fails, use the external Python bridge bot.

**Architecture:**
```
@akunito:akunito.com (Element)
    | E2E encrypted (matrix-nio[e2e])
Matrix Synapse (:8008)
    |
openclaw-matrix-bridge (Python systemd user service)
  |-- 3 AsyncClient instances (one per bot user)
  |-- Forwards messages to OpenClaw Chat Completions API
    | HTTP (localhost)
OpenClaw Gateway (:18789)
```

## Prerequisites

- VPS_PROD with NixOS profile
- Matrix Synapse running (docker)
- `pkgs.olm` in system packages (already included)
- OpenClaw gateway running on port 18789

## Setup (shared for both phases)

### 1. Create Matrix Bot Users

```bash
ssh -A -p 56777 akunito@100.64.0.6

# Register bot users (3 agents + 1 fallback monitor)
for bot in alfred vaultkeeper scout fallback; do
  docker exec synapse register_new_matrix_user \
    -c /data/homeserver.yaml \
    -u "${bot}bot" \
    -p '<STRONG_PASSWORD>' \
    http://localhost:8008
done

# Get access tokens
mkdir -p ~/.homelab/openclaw
for bot in alfred vaultkeeper scout fallback; do
  TOKEN=$(curl -s -X POST 'http://127.0.0.1:8008/_matrix/client/v3/login' \
    -H 'Content-Type: application/json' \
    -d "{\"type\":\"m.login.password\",\"identifier\":{\"type\":\"m.id.user\",\"user\":\"${bot}bot\"},\"password\":\"<PASSWORD>\",\"device_id\":\"OPENCLAW_${bot^^}\"}" \
    | jq -r '.access_token')
  echo "$TOKEN" > ~/.homelab/openclaw/matrix-token-$bot
  chmod 600 ~/.homelab/openclaw/matrix-token-$bot
done
```

### 2. Create E2E Rooms (in Element Web)

As `@akunito:akunito.com`:
1. Create private room "Alfred" -> enable E2E -> invite `@alfredbot:akunito.com` + `@fallbackbot:akunito.com`
2. Create private room "Vaultkeeper" -> enable E2E -> invite `@vaultkeeperbot:akunito.com` + `@fallbackbot:akunito.com`
3. Create private room "Scout" -> enable E2E -> invite `@scoutbot:akunito.com` + `@fallbackbot:akunito.com`
4. Record room IDs from room settings (Advanced tab)

### 3a. Phase A: Configure Native Plugin

Edit live `~/.openclaw/openclaw.json` on VPS (copy config from `openclaw.json.template`):
- Add `channels.matrix` with 3 accounts (alfred, vaultkeeper, scout)
- Add Matrix room bindings alongside Telegram bindings
- Set `encryption: true`, DM/group allowlists
- Replace `ALFRED_MATRIX_ROOM_ID` etc. with actual room IDs
- Replace access tokens with actual values

```bash
# Restart gateway to pick up new config
cd ~/.homelab/docker/openclaw && docker compose restart openclaw-gateway
```

### 3b. Phase B: Deploy External Bridge (if native plugin fails)

```bash
cd ~/.dotfiles

# Run setup scripts
bash templates/openclaw-matrix-bridge/setup.sh
bash templates/openclaw-matrix-fallback/setup.sh

# Edit configs with actual room IDs
nano ~/.openclaw-matrix-bridge/config.yaml
nano ~/.openclaw-matrix-fallback/config.yaml

# Start services
systemctl --user enable --now openclaw-matrix-bridge
systemctl --user enable --now openclaw-matrix-fallback
```

### 4. Deploy Telegram Fallback Monitor (both phases)

```bash
bash templates/openclaw-matrix-fallback/setup.sh

# Save Telegram bot token for fallback
echo '<TELEGRAM_BOT_TOKEN>' > ~/.homelab/openclaw/telegram-bot-token
chmod 600 ~/.homelab/openclaw/telegram-bot-token

nano ~/.openclaw-matrix-fallback/config.yaml
systemctl --user enable --now openclaw-matrix-fallback
```

### 5. Deploy NixOS (for systemd service definitions)

```bash
./install.sh ~/.dotfiles VPS_PROD -s -u -d
```

## Verification

1. Send message in each Matrix room -> verify encrypted response
2. Check encryption status in Element (lock icon on messages)
3. Test fallback: temporarily set `timeout_hours: 0.1` -> verify Telegram notification
4. Restart services -> verify E2E continues without re-verification

## Logs

```bash
# Phase A (native)
docker logs openclaw-gateway 2>&1 | grep matrix

# Phase B (external bridge)
journalctl --user -u openclaw-matrix-bridge -f

# Fallback monitor
journalctl --user -u openclaw-matrix-fallback -f
```

## Files

| File | Purpose |
|------|---------|
| `templates/openclaw/openclaw.json.template` | Native Matrix channel config (Phase A) |
| `templates/openclaw-matrix-bridge/bridge.py` | External bridge bot (Phase B) |
| `templates/openclaw-matrix-bridge/config.yaml` | Bridge configuration |
| `templates/openclaw-matrix-bridge/setup.sh` | Bridge installation |
| `templates/openclaw-matrix-fallback/fallback-monitor.py` | Fallback monitor |
| `templates/openclaw-matrix-fallback/config.yaml` | Fallback configuration |
| `templates/openclaw-matrix-fallback/setup.sh` | Fallback installation |
| `system/app/openclaw-matrix-bridge.nix` | NixOS systemd services |
| `lib/defaults.nix` | Feature flag (openclawMatrixBridgeEnable) |
