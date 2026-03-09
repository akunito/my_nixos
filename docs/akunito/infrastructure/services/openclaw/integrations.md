---
id: infrastructure.services.openclaw.integrations
summary: "OpenClaw integrations with existing VPS services: Plane, Matrix, n8n, Calendar, Postfix"
tags: [openclaw, integrations, plane, matrix, n8n, calendar, postfix, vps]
related_files: [profiles/VPS_PROD-config.nix, templates/openclaw/**]
date: 2026-03-09
status: published
---

# OpenClaw Integrations (VPS_PROD)

## Google Calendar (calendar-restricted MCP)

### Architecture

Same pattern as Gmail MCP: code-level RBAC wrapper around Google Calendar API.
OAuth token reused from n8n Google Calendar credential (same OAuth app, same scopes).
Credentials stored in `secrets/domains.nix`, token file at `~/.openclaw/credentials/calendar_mcp_token.json`.

### Tools (6 total)

| Tool | Description | Rate Limit |
|------|-------------|------------|
| `list_calendars` | List accessible calendars | — |
| `list_events` | List events by date range | — |
| `get_event` | Get event details by ID | — |
| `create_event` | Create new event | 10/hour |
| `update_event` | Update event time/title/description | 5/hour |
| `delete_event` | Delete event | 3/hour |

### Security

- OAuth scope: `calendar` + `calendar.events`
- Credentials volume mounted `:ro` — token refresh writes to `/tmp` (tmpfs)
- Input validation: max 50KB per field
- Rate limiting: persistent file-backed, fail-closed on corruption
- NOT implemented: ACL management, calendar creation/deletion, settings, freebusy

### Deploy Credentials

```bash
# 1. Create token file from n8n-extracted credentials (on VPS)
cat > ~/.openclaw/credentials/calendar_mcp_token.json << 'EOF'
{
  "client_id": "<from secrets/domains.nix: googleCalendarClientId>",
  "client_secret": "<from secrets/domains.nix: googleCalendarClientSecret>",
  "refresh_token": "<from secrets/domains.nix: googleCalendarRefreshToken>",
  "token_uri": "https://oauth2.googleapis.com/token",
  "scopes": ["https://www.googleapis.com/auth/calendar", "https://www.googleapis.com/auth/calendar.events"]
}
EOF
chmod 600 ~/.openclaw/credentials/calendar_mcp_token.json

# 2. Copy MCP script
cp templates/openclaw/calendar-restricted-mcp.py ~/.openclaw/mcp/calendar-restricted-mcp.py

# 3. Register in mcporter.json
# Add: "calendar": {"command": "python3", "args": ["/home/node/.openclaw/mcp/calendar-restricted-mcp.py"]}

# 4. Restart containers
cd ~/.homelab/openclaw && docker compose up -d
```

### Env Vars (docker-compose.yml)

```yaml
- CALENDAR_CREDENTIALS_PATH=/home/node/.openclaw/credentials
- CALENDAR_ACCOUNT=diego88aku@gmail.com
- CALENDAR_TIMEZONE=Europe/Madrid
```

### Capabilities

- "What events do I have today?"
- "Create a meeting with X tomorrow at 3pm"
- "Am I free Thursday afternoon?"
- "Move my 2pm to 4pm"
- Multi-calendar support (work + personal)

---

## Plane (Project Management)

### Problem

No `@anthropic/mcp-server-plane` npm package exists. Two approaches:

### Approach A: Custom Skill (Recommended)

Create `~/.openclaw/workspace/skills/plane/SKILL.md`:

```yaml
---
name: plane
description: Manage Plane project management tickets and pages
tools: [http]
---
```

Include: API base URL, auth header, workspace slug, project list with IDs, common operations, and the `/api/v1` vs `/api/` distinction for Pages.

### Approach B: MCP via mcporter

If a Plane MCP server is published:
```jsonc
{
  "mcpServers": {
    "plane-api": {
      "command": "npx",
      "args": ["-y", "ACTUAL_PACKAGE"],
      "env": {
        "PLANE_API_TOKEN": "TOKEN",
        "PLANE_API_URL": "http://host.docker.internal:3003/api/v1",
        "PLANE_WORKSPACE_SLUG": "akuworkspace"
      }
    }
  }
}
```

### API Notes

- Work items, projects, states, labels: `/api/v1/`
- Pages API: `/api/` (NOT `/api/v1/`)
- Auth header: `X-Api-Key: TOKEN`
- Generate token: Plane UI → Profile → API Tokens

### Test Connectivity

```bash
docker exec openclaw-gateway wget -qO- \
  --header="X-Api-Key: TOKEN" \
  http://host.docker.internal:3003/api/v1/workspaces/akuworkspace/projects/
```

---

## Matrix (Existing Synapse)

### Architecture

OpenClaw → Matrix plugin → localhost:8008 (Synapse on same VPS). Fully local, zero external traffic.

### Setup

```bash
# 1. Create bot account
docker exec matrix-synapse register_new_matrix_user \
  -u openclaw-bot -p "PASSWORD" -c /data/homeserver.yaml --no-admin

# 2. Get access token
curl -s -X POST http://127.0.0.1:8008/_matrix/client/r0/login \
  -H 'Content-Type: application/json' \
  -d '{"type":"m.login.password","user":"openclaw-bot","password":"PASSWORD"}' \
  | jq -r '.access_token'

# 3. Install plugin
docker compose --profile cli run --rm -T openclaw-cli plugins install @openclaw/matrix
```

### Config

```jsonc
{
  "channels": {
    "matrix": {
      "homeserver": "http://host.docker.internal:8008",
      "userId": "@openclaw-bot:matrix.akunito.com",
      "accessToken": "TOKEN",
      "dm": { "policy": "pairing" },
      "autoJoin": "allowlist",
      "autoJoinAllowlist": ["@akunito:matrix.akunito.com"],
      "groupPolicy": "allowlist",
      "encryption": true
    }
  }
}
```

**Note**: Matrix plugin uses `homeserver` (not `homeserverUrl`), `dm.policy` (nested object, not flat), and `autoJoin` is an enum (`"always"`, `"allowlist"`, `"off"`).

### Features

- E2EE support via `encryption: true` (Rust crypto SDK, requires device verification from Element)
- Federation (can interact with other Matrix servers)
- Threads, reactions, rich media
- Multi-account support via `channels.matrix.accounts`
- DM from Element: `@openclaw-bot:matrix.akunito.com`

---

## n8n (Workflow Automation)

### Bidirectional Integration

**n8n → OpenClaw** (trigger bot actions from workflows):
```bash
# n8n HTTP Request node
POST http://127.0.0.1:18789/hooks/agent
Headers: Authorization: Bearer ${OPENCLAW_HOOKS_TOKEN}
Body: {
  "message": "Backup completed: 2.3GB databases, 1.1GB services",
  "channel": "telegram",
  "to": "CHAT_ID"
}
```

**OpenClaw → n8n** (trigger workflows from chat):
User asks: "Trigger the backup verification workflow"
OpenClaw uses HTTP tool: `POST http://host.docker.internal:5678/webhook/WEBHOOK_ID`

### When to Use n8n vs OpenClaw Built-in

| Use case | Tool |
|----------|------|
| Simple scheduled messages | OpenClaw cron |
| Simple webhook triggers | OpenClaw hooks |
| Complex multi-step workflows | n8n |
| Data transformation pipelines | n8n |
| Third-party API orchestration | n8n |
| AI-powered responses to events | OpenClaw hooks → agent |

### n8n VPS Details

- Port: `localhost:5678`
- API key: `n8nApiKey` in `secrets/domains.nix`
- External: `https://n8n.akunito.com`
- Tailscale: `https://n8n.local.akunito.com`

---

## Postfix (Email Relay)

### Architecture

VPS Postfix (localhost:25) → SMTP2GO relay → internet.

### Config (if OpenClaw needs email)

```jsonc
{
  "tools": {
    "email": {
      "smtp": {
        "host": "host.docker.internal",
        "port": 25,
        "secure": false,
        "from": "openclaw@akunito.com"
      }
    }
  }
}
```

### Use Cases

- Calendar invite emails
- Notification digests
- Alert summaries
- Most notifications go through Telegram/Discord/Matrix — email is optional

---

## Redis (Optional)

db5 is available on `localhost:6379` (password in `secrets/domains.nix`).

Use if OpenClaw session data grows large:
- Session store backend
- Caching layer
- Rate limiting state

Access from Docker: `host.docker.internal:6379`

---

## Monitoring Integration

### Uptime Kuma (status.akunito.com)

Add monitors:
1. **OpenClaw Health**: HTTP, `http://127.0.0.1:18789/healthz`, 60s interval
2. **OpenClaw Ready**: HTTP, `http://127.0.0.1:18789/readyz`, 60s interval

### Prometheus (if metrics available)

If OpenClaw exposes `/metrics`, add scrape target in VPS_PROD-config.nix:
```nix
{ job_name = "openclaw"; targets = ["127.0.0.1:18789"]; path = "/metrics"; }
```

### Restic Backup

Include in services backup (daily 09:00):
```nix
"/home/akunito/.openclaw"
"/home/akunito/.homelab/openclaw"
```

Covers: config, credentials, session history, cron jobs, .env file.
