# OpenClaw Matrix Bridge

E2E-encrypted Matrix channels for OpenClaw agents (Alfred, Vaultkeeper, Scout) with Telegram fallback notifications.

## Architecture

```
@akunito:akunito.com (Element)
    | E2E encrypted (matrix-nio[e2e])
Matrix Synapse (:8008)
    |
openclaw-matrix-bridge (Python systemd user service)
  |-- 3 AsyncClient instances (one per bot user, each with own crypto store)
  |-- Maps rooms -> agents
  |-- Forwards user messages -> OpenClaw HTTP API
  |-- Forwards agent responses -> Matrix rooms
    | HTTP (localhost)
OpenClaw Gateway (:18789)
```

## Prerequisites

- VPS_PROD with NixOS profile
- Matrix Synapse running (docker)
- `pkgs.olm` in system packages (already included)
- OpenClaw gateway running on port 18789

## Deployment (Two-Phase)

### Phase A: Check Native Matrix Plugin

Before using the external bridge, check if OpenClaw has native Matrix support:

```bash
ssh -A -p 56777 akunito@100.64.0.6

docker exec openclaw-gateway ls /app/extensions/ 2>/dev/null
docker exec openclaw-gateway ls /app/node_modules/@openclaw/ 2>/dev/null | grep -i matrix
docker logs openclaw-gateway 2>&1 | grep -i matrix
```

If native support exists, configure it in `openclaw.json` directly and skip Phase B.

### Phase B: External Bridge (if no native plugin)

#### 1. Create Matrix Bot Users

```bash
ssh -A -p 56777 akunito@100.64.0.6

# Register bot users
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

#### 2. Create E2E Rooms (in Element Web)

As `@akunito:akunito.com`:
1. Create private room "Alfred" -> enable E2E -> invite `@alfredbot:akunito.com` + `@fallbackbot:akunito.com`
2. Create private room "Vaultkeeper" -> enable E2E -> invite `@vaultkeeperbot:akunito.com` + `@fallbackbot:akunito.com`
3. Create private room "Scout" -> enable E2E -> invite `@scoutbot:akunito.com` + `@fallbackbot:akunito.com`
4. Record room IDs from room settings (Advanced tab)

#### 3. Deploy Bridge + Fallback

```bash
# Pull latest dotfiles
cd ~/.dotfiles && git fetch origin && git reset --hard origin/main

# Run setup scripts
bash templates/openclaw-matrix-bridge/setup.sh
bash templates/openclaw-matrix-fallback/setup.sh

# Edit configs with actual room IDs
nano ~/.openclaw-matrix-bridge/config.yaml
nano ~/.openclaw-matrix-fallback/config.yaml

# Save Telegram bot token for fallback
echo '<TELEGRAM_BOT_TOKEN>' > ~/.homelab/openclaw/telegram-bot-token
chmod 600 ~/.homelab/openclaw/telegram-bot-token

# Start services
systemctl --user enable --now openclaw-matrix-bridge
systemctl --user enable --now openclaw-matrix-fallback
```

#### 4. Deploy NixOS (for systemd service definitions)

```bash
./install.sh ~/.dotfiles VPS_PROD -s -u -d
```

## Verification

1. Send message in each Matrix room -> verify encrypted response
2. Check encryption status: `/status` command in any room
3. Test fallback: temporarily set `timeout_hours: 0.1` -> verify Telegram notification
4. Restart services -> verify E2E continues without re-verification

## Logs

```bash
journalctl --user -u openclaw-matrix-bridge -f
journalctl --user -u openclaw-matrix-fallback -f
```

## Files

| File | Purpose |
|------|---------|
| `templates/openclaw-matrix-bridge/bridge.py` | Main bridge bot |
| `templates/openclaw-matrix-bridge/config.yaml` | Bridge configuration |
| `templates/openclaw-matrix-bridge/setup.sh` | Installation script |
| `templates/openclaw-matrix-fallback/fallback-monitor.py` | Fallback monitor |
| `templates/openclaw-matrix-fallback/config.yaml` | Fallback configuration |
| `templates/openclaw-matrix-fallback/setup.sh` | Fallback installation |
| `system/app/openclaw-matrix-bridge.nix` | NixOS systemd services |
| `lib/defaults.nix` | Feature flag (openclawMatrixBridgeEnable) |
