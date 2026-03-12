---
id: infrastructure.services.openclaw.automation
summary: "OpenClaw automation: cron jobs, webhooks, hooks, and Gmail PubSub"
tags: [openclaw, automation, cron, webhooks, hooks, gmail, n8n]
date: 2026-03-04
status: published
---

# OpenClaw Automation

## Cron Jobs (Built-in Scheduler)

OpenClaw has native scheduled task support — no n8n needed for simple automation.

### Configuration

```jsonc
{
  "cron": {
    "enabled": true,
    "maxConcurrentRuns": 1,
    "sessionRetention": "24h",
    "runLog": { "maxBytes": "2mb", "keepLines": 2000 }
  }
}
```

Jobs persist in `~/.openclaw/cron/jobs.json` and survive restarts.

### Schedule Types

| Type | Format | Behavior |
|------|--------|----------|
| `--at` | ISO 8601 timestamp | One-shot, auto-deletes after success |
| `--every` | Milliseconds | Fixed interval |
| `--cron` | 5/6-field cron expression | Recurring, with IANA timezone |

Top-of-hour jobs get deterministic stagger (up to 5min). Use `--exact` to disable.

### Execution Modes

| Mode | Session | Context |
|------|---------|---------|
| Main | `main` | Enqueues system event in normal agent session |
| Isolated | `cron:<jobId>` | Dedicated agent turn, no main conversation history |

### Delivery Options (Isolated Jobs)

- **Announce**: Posts output via channel adapters (Telegram, Discord, Slack, etc.)
- **Webhook**: HTTP POST to URL on completion
- **None**: Internal only

### CLI Examples

```bash
# Daily morning brief at 08:00 Warsaw time → Telegram
openclaw cron add --name "morning-brief" \
  --cron "0 8 * * *" --tz "Europe/Warsaw" \
  --session isolated \
  --message "Summarize calendar and overdue Plane tickets" \
  --announce --channel telegram --to "CHAT_ID"

# One-shot reminder
openclaw cron add --name "meeting-prep" \
  --at "2026-03-05T14:00:00+01:00" \
  --session main --system-event "Prepare for 3pm meeting" --wake now

# Weekly review Sunday 19:00
openclaw cron add --name "weekly-review" \
  --cron "0 19 * * 0" --tz "Europe/Warsaw" \
  --session isolated --agent main \
  --message "Create weekly review summary" \
  --announce --channel telegram --to "CHAT_ID"

# List / manage jobs
openclaw cron list
openclaw cron remove <jobId>
```

### Agent Binding

Pin jobs to specific agents in multi-agent setups:
```bash
openclaw cron add --name "ops-check" --cron "0 6 * * *" \
  --session isolated --agent ops
```

### Error Handling

- Transient errors (429, network, 5xx): exponential backoff retry
- Permanent errors (auth, validation): disable immediately
- One-shot: up to 3 retries. Recurring: backoff 30s → 1h before next scheduled run

---

## Webhooks (External HTTP Triggers)

### Configuration

```jsonc
{
  "hooks": {
    "enabled": true,
    "token": "${OPENCLAW_HOOKS_TOKEN}",
    "path": "/hooks",
    "allowedAgentIds": ["hooks", "main"],
    "allowRequestSessionKey": false,
    "allowedSessionKeyPrefixes": ["hook:"],
    "defaultSessionKey": "hook:ingress"
  }
}
```

### Authentication

Every request must include the hook token via:
- `Authorization: Bearer <token>` (recommended)
- `x-openclaw-token: <token>` (alternative)
- Query-string tokens rejected (400)

### Endpoints

#### POST /hooks/wake

Triggers system event in main session:
```bash
curl -X POST http://127.0.0.1:18789/hooks/wake \
  -H "Authorization: Bearer SECRET" \
  -H "Content-Type: application/json" \
  -d '{"text":"Backup completed","mode":"now"}'
```

#### POST /hooks/agent

Runs isolated agent turn:
```bash
curl -X POST http://127.0.0.1:18789/hooks/agent \
  -H "Authorization: Bearer SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Summarize recent alerts",
    "name": "Monitor",
    "channel": "telegram",
    "to": "CHAT_ID",
    "model": "modelstudio/qwen3.5-plus",
    "timeoutSeconds": 120
  }'
```

Parameters: `message` (required), `agentId`, `channel` (`last|telegram|discord|slack|...`), `to`, `model`, `thinking`, `deliver` (default true), `timeoutSeconds`.

### Custom Mappings

Transform arbitrary payloads into wake/agent actions:
```jsonc
{
  "hooks": {
    "presets": ["gmail"],
    "mappings": [{
      "match": { "path": "custom" },
      "action": "agent",
      "messageTemplate": "Event: {{data.type}}"
    }]
  }
}
```

### n8n Integration Pattern

**n8n → OpenClaw**: n8n HTTP Request node calls `/hooks/agent`:
```
URL: http://127.0.0.1:18789/hooks/agent
Headers: Authorization: Bearer ${OPENCLAW_HOOKS_TOKEN}
Body: {"message":"Workflow result: ...","channel":"telegram","to":"CHAT_ID"}
```

**OpenClaw → n8n**: User asks OpenClaw to trigger workflow. OpenClaw uses HTTP tool:
```
POST http://host.docker.internal:5678/webhook/WEBHOOK_ID
```

---

## Internal Hooks (Event-Driven Scripts)

### Discovery Directories (precedence)

1. `<workspace>/hooks/` (highest)
2. `~/.openclaw/hooks/` (user-installed)
3. `<openclaw>/dist/hooks/bundled/` (shipped)

### Supported Events

| Category | Events |
|----------|--------|
| Command | `command`, `command:new`, `command:reset`, `command:stop` |
| Agent | `agent:bootstrap` |
| Gateway | `gateway:startup` |
| Message | `message:received`, `message:transcribed`, `message:preprocessed`, `message:sent` |
| Plugin | `tool_result_persist` (synchronous) |

### Bundled Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `session-memory` | `command:new` | Saves context to `memory/YYYY-MM-DD-slug.md` |
| `bootstrap-extra-files` | `agent:bootstrap` | Injects additional files via glob |
| `command-logger` | `command` | Audit trail at `logs/commands.log` (JSONL) |
| `boot-md` | `gateway:startup` | Executes `BOOT.md` instructions on startup |

### Custom Hook Structure

```
hooks/my-hook/
├── HOOK.md        # Metadata (YAML frontmatter)
└── handler.ts     # Implementation
```

### CLI

```bash
openclaw hooks list [--eligible] [--verbose]
openclaw hooks enable <name>
openclaw hooks disable <name>
openclaw hooks install <path-or-npm-spec>
```

---

## Gmail PubSub Integration

Architecture: Gmail watch → Google Cloud Pub/Sub → `gog gmail watch serve` → OpenClaw webhook.

```bash
# GCP setup
gcloud pubsub topics create gog-gmail-watch
gcloud pubsub topics add-iam-policy-binding gog-gmail-watch \
  --member=serviceAccount:gmail-api-push@system.gserviceaccount.com \
  --role=roles/pubsub.publisher

# Start watch
gog gmail watch start --account user@gmail.com --label INBOX \
  --topic projects/<id>/topics/gog-gmail-watch

# Run handler
openclaw webhooks gmail run
```

Config: `hooks.presets: ["gmail"]` enables built-in Gmail mapping.
