---
id: infrastructure.services.openclaw.docker
summary: "OpenClaw Docker deployment for VPS_PROD with rootless Docker"
tags: [openclaw, docker, vps, deployment, rootless]
date: 2026-03-04
status: published
---

# OpenClaw Docker Deployment

## VPS_PROD Context

- **Docker mode**: Rootless (runs as user `akunito`, uid 1000)
- **Socket**: `/run/user/1000/docker.sock`
- **Host gateway**: `10.0.2.2` (slirp4netns NAT — for accessing host services like PostgreSQL, Redis, Postfix)
- **Port binding**: All ports bound to `127.0.0.1` only
- **Orchestration**: `homelab-docker.service` (systemd oneshot, managed by `system/app/homelab-docker.nix`)

## Docker Compose Reference

```yaml
services:
  openclaw-gateway:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw-gateway
    init: true                          # Proper signal handling
    restart: unless-stopped
    user: "1000:1000"                   # Rootless Docker convention
    security_opt:
      - no-new-privileges:true
    ports:
      - "127.0.0.1:18789:18789"        # Gateway (localhost only)
      - "127.0.0.1:18790:18790"        # Bridge (Nodes/mobile integration)
    extra_hosts:
      - "host.docker.internal:10.0.2.2" # slirp4netns host gateway
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_PORT=18789
      - MODELSTUDIO_API_KEY=${MODELSTUDIO_API_KEY}
      - GROQ_API_KEY=${GROQ_API_KEY}
      - OPENCLAW_HOOKS_TOKEN=${OPENCLAW_HOOKS_TOKEN}
      - TZ=Europe/Madrid
    volumes:
      - ${HOME}/.openclaw:/home/node/.openclaw
      - openclaw_workspace:/home/node/workspace
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M
    healthcheck:
      test: ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:18789/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))\""]
      interval: 60s
      timeout: 15s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "3"

  openclaw-cli:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw-cli
    network_mode: "service:openclaw-gateway"   # Shares gateway network
    profiles: ["cli"]                          # Only runs on demand
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - NET_RAW
      - NET_ADMIN
    environment:
      - HOME=/home/node
      - TERM=xterm-256color
    volumes:
      - ${HOME}/.openclaw:/home/node/.openclaw
    entrypoint: ["openclaw"]

volumes:
  openclaw_workspace:
    driver: local
```

## Running CLI Commands

The CLI container shares the gateway's network namespace (loopback access):

```bash
# Run any openclaw command
docker compose --profile cli run --rm -T openclaw-cli <command>

# Examples
docker compose --profile cli run --rm -T openclaw-cli channels add telegram --token "TOKEN"
docker compose --profile cli run --rm -T openclaw-cli security audit --deep
docker compose --profile cli run --rm -T openclaw-cli cron list
docker compose --profile cli run --rm -T openclaw-cli gateway probe
```

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `OPENCLAW_IMAGE` | Pre-built image (e.g., `ghcr.io/openclaw/openclaw:latest`) |
| `OPENCLAW_GATEWAY_PORT` | Gateway port (default 18789) |
| `OPENCLAW_DOCKER_APT_PACKAGES` | Extra system packages during build |
| `OPENCLAW_EXTRA_MOUNTS` | Comma-separated bind mounts |
| `OPENCLAW_HOME_VOLUME` | Named volume for `/home/node` |
| `OPENCLAW_SANDBOX` | Enable Docker sandbox (`1`/`true`) |
| `OPENCLAW_DOCKER_SOCKET` | Override socket path (rootless: `/run/user/1000/docker.sock`) |

## Health Checks

```bash
curl -fsS http://127.0.0.1:18789/healthz   # Health status (unauthenticated)
curl -fsS http://127.0.0.1:18789/readyz     # Readiness status (unauthenticated)

# Authenticated diagnostics
docker compose --profile cli run --rm -T openclaw-cli health --token "$TOKEN"
```

## Rootless Docker Specifics

- Container runs as `node` (uid 1000) — matches VPS `akunito` user
- Host services accessible via `host.docker.internal` → `10.0.2.2`
- DNS: Must use explicit servers (1.1.1.1, 9.9.9.9) — `127.0.0.53` unreachable via slirp4netns
- Kernel sysctl `net.ipv4.ip_unprivileged_port_start = 80` allows binding ports 80+

## File Permissions

```bash
chmod 600 ~/.homelab/openclaw/.env
chmod 700 ~/.openclaw
chmod 600 ~/.openclaw/openclaw.json
chmod 700 ~/.openclaw/credentials
chown -R 1000:1000 ~/.openclaw   # Match Docker uid
```

## VPS Integration Points

| Service | Access from Docker | Address |
|---------|-------------------|---------|
| Plane | `host.docker.internal:3003` | Via slirp4netns |
| Matrix Synapse | `host.docker.internal:8008` | Via slirp4netns |
| PostgreSQL | `host.docker.internal:5432` | If OpenClaw needs DB |
| Redis | `host.docker.internal:6379` | db5 available |
| Postfix | `host.docker.internal:25` | SMTP relay |
| n8n | `host.docker.internal:5678` | Webhook triggers |
| nginx-local | `openclaw.local.akunito.com` | Tailscale access |

## Resource Budget

| Resource | Allocation |
|----------|-----------|
| Memory limit | 1 GB |
| Memory reservation | 256 MB |
| CPU | Shared (API proxy — low usage) |
| Disk | ~500 MB (config, sessions, credentials) |
| VPS headroom | ~14 GB RAM free before OpenClaw |
