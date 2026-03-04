---
id: infrastructure.services.openclaw.tools
summary: "OpenClaw tools: browser automation, exec, Lobster workflows, sub-agents"
tags: [openclaw, tools, browser, playwright, exec, lobster, subagents]
date: 2026-03-04
status: published
---

# OpenClaw Tools

## Browser Automation

Agent-controlled browser via Chrome DevTools Protocol (CDP) with Playwright.

### Profile Types

| Type | Description |
|------|-------------|
| `openclaw` (managed) | Dedicated isolated Chromium instance |
| `chrome` (extension) | Controls existing Chrome tabs via extension |
| `remote` (CDP) | Explicit CDP URL to remote browser |

### Configuration

```jsonc
{
  "browser": {
    "enabled": true,
    "headless": false,
    "defaultProfile": "openclaw",
    "ssrfPolicy": {
      "dangerouslyAllowPrivateNetwork": true,
      "allowedHostnames": ["localhost"]
    },
    "profiles": {
      "openclaw": { "cdpPort": 18800 },
      "work": { "cdpPort": 18801 },
      "remote": { "cdpUrl": "http://10.0.0.42:9222" }
    }
  }
}
```

### Key Commands

```bash
openclaw browser start / stop / status
openclaw browser navigate <url>
openclaw browser click <ref> [--double]
openclaw browser type <ref> "text" [--submit]
openclaw browser screenshot [--full-page]
openclaw browser snapshot [--interactive]
openclaw browser pdf
openclaw browser evaluate --fn '(el) => el.textContent'
```

### Port Architecture

| Service | Default Port |
|---------|-------------|
| Gateway | 18791 |
| Relay | Gateway + 1 |
| Control | Gateway + 2 |
| CDP ports | 18800-18899 (per profile) |

### Security

- Loopback-only control service
- Auto-generated auth tokens
- SSRF policy configuration
- `browser.evaluateEnabled: false` to block arbitrary JS
- Sandbox: dedicated network `openclaw-sandbox-browser`

---

## Exec Tool

Host command execution with fine-grained approval control.

### Security Modes

| Mode | Behavior |
|------|----------|
| `deny` | Block all host exec (safest) |
| `allowlist` | Only allowlisted binaries |
| `full` | Allow everything (dangerous) |

### Approval Workflow

1. Gateway broadcasts `exec.approval.requested`
2. Control UI or chat channel shows approval prompt
3. User responds: "Allow once", "Always allow", "Deny"
4. Approved commands execute on host

### Chat Forwarding

Route approval requests to Telegram/Slack/Discord:
```jsonc
{
  "approvals": {
    "exec": {
      "enabled": true,
      "targets": [{ "channel": "telegram", "to": "CHAT_ID" }]
    }
  }
}
```

Reply: `/approve <id> allow-once|allow-always|deny`

---

## Lobster Typed Workflows

Deterministic multi-step tool sequences as a single operation. Local subprocess model.

### Enable

```jsonc
{ "tools": { "alsoAllow": ["lobster"] } }
```

### Pipeline Syntax

```
inbox list --json | inbox categorize --json | inbox apply --json
```

### Workflow Files (.lobster/.yaml)

```yaml
name: inbox-triage
args:
  tag: { default: "family" }
steps:
  - id: collect
    command: inbox list --json
  - id: categorize
    command: inbox categorize --json
    stdin: $collect.stdout
  - id: approve
    command: inbox apply --approve
    stdin: $categorize.stdout
    approval: required
  - id: execute
    command: inbox apply --execute
    stdin: $categorize.stdout
    condition: $approve.approved
```

Data passing: `$step.stdout` (raw), `$step.json` (parsed), `$step.approved` (boolean).

### LLM-Task Tool (structured AI operations in pipelines)

```bash
openclaw.invoke --tool llm-task --action json --args-json '{
  "prompt": "Classify this email",
  "input": { "subject": "Hello" },
  "schema": { "type": "object", "properties": { "intent": {"type":"string"} } }
}'
```

### Response Envelope

| Status | Meaning |
|--------|---------|
| `ok` | Completed, `output` field available |
| `needs_approval` | Paused, `resumeToken` for continuation |
| `cancelled` | Denied by user |

---

## Sub-Agents

Isolated background runs spawned from primary sessions.

### Spawn

```bash
/subagents spawn <agentId> <task> [--model <model>] [--thinking <level>]
```

### Management

```bash
/subagents list                    # Active sub-agents
/subagents info <id>               # Metadata
/subagents log <id> [limit]        # Execution logs
/subagents kill <id|all>           # Terminate
/subagents send <id> <message>     # Send message
/subagents steer <id> <message>    # Direct execution
```

### Configuration

```jsonc
{
  "agents": {
    "defaults": {
      "subagents": {
        "model": "<model>",
        "thinking": "<level>",
        "runTimeoutSeconds": 900,
        "archiveAfterMinutes": 60,
        "maxSpawnDepth": 1,
        "maxChildrenPerAgent": 5,
        "maxConcurrent": 8
      }
    }
  }
}
```

### Nesting

| Depth | Role | Can spawn? |
|-------|------|------------|
| 0 | Primary agent | Always |
| 1 | Orchestrator/leaf | If `maxSpawnDepth >= 2` |
| 2 | Worker | Never |

### Thread Binding (Discord)

- `/focus <target>` — bind thread to sub-agent
- `/unfocus` — remove binding
- `/session idle <duration>` — auto-unfocus on inactivity
- `/stop` cascades to all child agents
