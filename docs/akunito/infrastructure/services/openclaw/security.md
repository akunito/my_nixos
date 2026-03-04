---
id: infrastructure.services.openclaw.security
summary: "OpenClaw security: authentication, sandboxing, secrets, and hardening"
tags: [openclaw, security, authentication, sandbox, secrets, hardening]
date: 2026-03-04
status: published
---

# OpenClaw Security

## Authentication Modes

### Gateway Auth

| Mode | Use case |
|------|----------|
| `token` | Shared bearer token for all clients (**recommended**) |
| `password` | Via `OPENCLAW_GATEWAY_PASSWORD` env var |
| `trusted-proxy` | Delegates to reverse proxy with header-based identity |

Generate token: `openclaw doctor --generate-gateway-token`

Rate limiting protects against brute-force, with loopback exemptions.

### Model Provider Auth

Priority (highest to lowest):
1. `OPENCLAW_LIVE_<PROVIDER>_KEY` (override)
2. `<PROVIDER>_API_KEYS` (comma-separated list)
3. `<PROVIDER>_API_KEY` (standard)
4. `<PROVIDER>_API_KEY_*` (numbered variants)

On rate-limit (HTTP 429), auto-retries with next available credential.

Check status: `openclaw models status --check` (exit 1 = missing/expired, exit 2 = expiring)

## Tool Permissions

### Profiles

| Profile | Allows | Use case |
|---------|--------|----------|
| `messaging` | Safe tools only, no shell/filesystem/elevated | **Recommended for chat bots** |
| (custom) | Configurable allow/deny lists | Advanced |

### Permission Controls

```jsonc
{
  "tools": {
    "profile": "messaging",
    "deny": ["group:automation", "group:runtime", "sessions_spawn", "sessions_send"],
    "fs": { "workspaceOnly": true },
    "exec": { "security": "deny", "ask": "always" },
    "elevated": { "enabled": false }
  }
}
```

- `fs.workspaceOnly: true` — restricts file access to workspace directory
- `exec.security: "deny"` — blocks all shell execution
- `elevated.enabled: false` — no host-level commands
- `deny` groups: `automation` (cron/gateway tools), `runtime` (process control)

### Exec Approval System

Config: `~/.openclaw/exec-approvals.json`

| Security mode | Behavior |
|---------------|----------|
| `deny` | Block all host exec |
| `allowlist` | Only allowlisted binaries |
| `full` | Allow everything (elevated) |

Ask modes: `off`, `on-miss` (prompt when not in allowlist), `always`.

Safe bins (stdin-only, no file args): `jq`, `cut`, `uniq`, `head`, `tail`, `tr`, `wc`.

Approval forwarding to chat channels:
```jsonc
{
  "approvals": {
    "exec": {
      "targets": [{ "channel": "telegram", "to": "CHAT_ID" }]
    }
  }
}
```

## Sandboxing (Docker Isolation)

### Modes

| Mode | Behavior |
|------|----------|
| `off` | No sandboxing |
| `non-main` | Only non-primary sessions sandboxed |
| `all` | Every session runs in isolated container |

### Scope

| Scope | Isolation level |
|-------|----------------|
| `session` | One container per user session (default) |
| `agent` | One container per agent across sessions |
| `shared` | Single container for all sandboxed sessions |

### Workspace Access

| Value | Behavior |
|-------|----------|
| `none` | Isolated workspace (default) |
| `ro` | Read-only mount at `/agent` |
| `rw` | Read-write mount at `/workspace` |

### Config

```jsonc
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "non-main",
        "docker": { "image": "openclaw-sandbox:bookworm-slim" }
      }
    }
  }
}
```

Build sandbox image: `scripts/sandbox-setup.sh`
Debug: `openclaw sandbox explain`

Sandboxed tools: `exec`, `read`, `write`, `edit`, `apply_patch`, `process`, browser.
Non-sandboxed: Gateway process, host-configured tools, elevated exec.

### Container Security

- Network: `none` by default (no egress)
- Dangerous mounts blocked: `docker.sock`, `/etc`, `/proc`, `/sys`, `/dev`
- Chrome browser in sandbox: separate network `openclaw-sandbox-browser`

## Secrets Management

### SecretRef System

All secrets use unified references:
```jsonc
{ "source": "env" | "file" | "exec", "provider": "default", "id": "..." }
```

Three backends:
1. **Environment variables**: `id` = env var name
2. **File provider**: JSON pointer resolution, permission checks
3. **Exec provider**: Runs binary, expects JSON response

Activation is **eager** (resolved at startup, fail-fast). Failed resolution keeps last-known-good snapshot.

### CLI

```bash
openclaw secrets audit --check       # Verify secret hygiene
openclaw secrets configure           # Setup wizard
openclaw secrets apply --dry-run     # Preview changes
```

## Hardening Checklist

- [x] Use `token` auth mode with strong random token
- [x] Bind to `loopback` (native) or `lan` behind Tailscale (Docker)
- [x] Set `tools.profile: "messaging"` for chat use
- [x] Deny `group:automation`, `group:runtime` tools
- [x] Enable `fs.workspaceOnly: true`
- [x] Disable elevated mode
- [x] Use `dmPolicy: "pairing"` (not "open")
- [x] Require mention in groups (`requireMention: true`)
- [x] Disable mDNS (`discovery.mdns.mode: "off"`)
- [x] Enable log redaction (`logging.redactSensitive: "tools"`)
- [x] Separate webhook token from gateway token
- [x] Disable `allowRequestSessionKey` on hooks
- [x] Run `openclaw security audit --deep` after config changes
- [x] Set file permissions: 600 (config), 700 (directories)
- [ ] Enable sandbox mode once stable (`sandbox.mode: "non-main"`)
- [ ] Audit community skills before install (ClawHavoc: 341+ malicious)

## Trust Model

OpenClaw targets **personal-assistant deployment** (one trusted operator). It is NOT designed for hostile multi-tenant isolation. Session keys are routing selectors, not per-user auth. For adversarial isolation, use separate gateways + credentials + OS users.
