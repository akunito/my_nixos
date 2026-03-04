---
id: infrastructure.services.openclaw.architecture
summary: "OpenClaw gateway architecture, deployment modes, and filesystem layout"
tags: [openclaw, architecture, gateway, deployment]
date: 2026-03-04
status: published
---

# OpenClaw Architecture

## Gateway Model

OpenClaw runs a single **Gateway** process that multiplexes WebSocket and HTTP on one port (default 18789). The Gateway manages:

- **Pi agent runtime** (RPC mode with tool/block streaming)
- **CLI interface** (via `openclaw-cli` container sharing network namespace)
- **WebChat UI** (browser-based control panel at `http://127.0.0.1:18789/`)
- **Channel adapters** (Telegram, Discord, Matrix, etc. — all outbound connections)
- **Webhook endpoints** (`/hooks/*` for external triggers)
- **Health probes** (`/healthz`, `/readyz` — unauthenticated)

## Deployment Modes

### Docker (recommended for VPS)

Two-container pattern:
- **openclaw-gateway**: Main runtime, runs as user `node` (uid 1000)
- **openclaw-cli**: Admin commands, shares gateway's network namespace

```bash
# Pre-built image
export OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
./docker-setup.sh

# Or manual compose
docker compose up -d openclaw-gateway
docker compose --profile cli run --rm -T openclaw-cli <command>
```

Image tags: `latest` (stable), `main` (dev), version-specific (e.g., `2026.2.26`).

### Native (npm)

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
openclaw gateway --port 18789 --verbose
```

### Remote Gateway (SSH tunnel)

For accessing a VPS gateway from local machines:
```
Host remote-gateway
    HostName <VPS_IP>
    LocalForward 18789 127.0.0.1:18789
```
Alternative: Tailscale Serve (tailnet-only) or Tailscale Funnel (public).

## Binding Modes

| Mode | Scope | Use case |
|------|-------|----------|
| `loopback` | Container-internal only | Not suitable for Docker (blocks port publishing) |
| `lan` | Host + LAN access | **Required for Docker** — allows host to reach published port |
| Custom | Specific interface | Advanced setups |

**Important for Docker**: Must use `bind: "lan"`. Loopback binding prevents the host from accessing the published port.

## Filesystem Layout

```
~/.openclaw/
├── openclaw.json              # Main gateway configuration
├── .env                       # API keys (daemon access)
├── workspace/                 # Agent workspace root
│   ├── AGENTS.md              # Injected agent context
│   ├── SOUL.md                # Personality/behavior
│   ├── TOOLS.md               # Tool documentation
│   └── skills/                # Custom skills
│       └── <skill>/SKILL.md
├── agents/
│   └── <agentId>/
│       ├── agent/
│       │   └── auth-profiles.json
│       └── sessions/
│           └── *.jsonl        # Session transcripts
├── credentials/
│   ├── google/                # OAuth credentials
│   ├── whatsapp/              # WhatsApp pairing state
│   └── matrix/                # Matrix access tokens
├── cron/
│   └── jobs.json              # Scheduled job definitions
├── hooks/                     # User-installed hooks
├── sandboxes/                 # Sandbox isolated workspaces
├── settings/
│   ├── tts.json               # TTS preferences
│   └── voicewake.json         # Voice wake triggers
└── logs/
    └── commands.log           # Audit trail (JSONL)
```

## Model Provider Configuration

OpenClaw supports multiple AI providers simultaneously with fallback chains:

```jsonc
{
  "models": {
    "mode": "merge",
    "providers": {
      "modelstudio": {
        "baseUrl": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        "apiKey": "${MODELSTUDIO_API_KEY}",
        "api": "openai-completions",
        "models": [
          { "id": "qwen3.5-plus", "name": "Qwen 3.5 Plus",
            "contextWindow": 131072, "maxTokens": 8192 }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "modelstudio/qwen3.5-plus" }
    }
  }
}
```

Built-in support for: Anthropic, OpenAI, Google, Groq, Cerebras, MiniMax, Moonshot, custom OpenAI-compatible endpoints, and local models via LM Studio.

## Session Management

- **Isolation**: `per-channel-peer` (each user per channel gets own session)
- **Compaction**: Summarizes long histories preserving key identifiers
- **Daily/idle reset**: Configurable automatic session cleanup
- **Thread binding**: Discord threads bind to sub-agent sessions

## In-Chat Commands

Available in all channels: `/status`, `/new`, `/reset`, `/compact`, `/think <level>`, `/verbose on|off`, `/usage off|tokens|full`, `/activation mention|always`, `/tts off|always`.

## Update Channels

| Channel | npm tag | Use case |
|---------|---------|----------|
| `stable` | `latest` | Production |
| `beta` | `beta` | Pre-release testing |
| `dev` | `dev` | Bleeding edge |

Switch: `openclaw update --channel stable|beta|dev`
