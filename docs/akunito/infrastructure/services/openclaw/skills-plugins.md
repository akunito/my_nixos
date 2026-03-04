---
id: infrastructure.services.openclaw.skills
summary: "OpenClaw skills, MCP servers, plugins, and the community ecosystem"
tags: [openclaw, skills, mcp, plugins, community, clawhub]
date: 2026-03-04
status: published
---

# OpenClaw Skills & Plugins

## Skills System

Skills are markdown-based instructions that extend OpenClaw's capabilities. Each skill is a directory containing a `SKILL.md` file with YAML frontmatter and instructions.

### Skill Structure

```
~/.openclaw/workspace/skills/
└── my-skill/
    ├── SKILL.md          # Required: metadata + instructions
    └── (optional files)  # Scripts, templates, data
```

### SKILL.md Format

```yaml
---
name: my_skill
description: One-line description of what this skill does
tools: [http, bash]       # Tools the skill may use
---

# Instructions for the AI model

When asked to do X, follow these steps:
1. ...
2. ...
```

### Configuration

```jsonc
{
  "skills": {
    "load": {
      "extraDirs": ["/path/to/more/skills"],  // Additional search paths
      "watch": true,                           // Auto-detect changes
      "watchDebounceMs": 250
    },
    "install": {
      "preferBrew": true,
      "nodeManager": "npm"                     // npm | pnpm | yarn | bun
    },
    "allowBundled": ["gog", "skill2"],         // Whitelist bundled skills
    "entries": {
      "gog": {
        "enabled": true,
        "config": { "services": ["calendar"] },
        "env": { "CUSTOM_VAR": "value" },
        "apiKey": "key-or-secretref"
      }
    }
  }
}
```

### Built-in Skills

| Skill | Purpose |
|-------|---------|
| `gog` | Google services (Calendar, Gmail, Drive, Docs) |
| `mcporter` | MCP client/manager CLI — easiest path to call custom MCP tools |
| `calctl` | Apple Calendar via icalBuddy + AppleScript (macOS only) |

### Community Skills (5,400+ in registry)

**Registry**: https://github.com/VoltAgent/awesome-openclaw-skills

Notable categories:
- **Calendar & Scheduling** (61 skills)
- **Productivity & Tasks** (206 skills)
- **Monitoring & Observability** (agent-metrics, agent-watcher)
- **Infrastructure** (agentic-devops — Docker, process management)

**SECURITY WARNING**: The ClawHavoc campaign identified 341+ malicious skills in the registry. **Always audit skills before installing.** Only use skills from the official `openclaw/skills` repository or thoroughly reviewed community packages.

---

## MCP Server Integration

OpenClaw supports MCP (Model Context Protocol) servers natively via config.

### Configuration

```jsonc
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@package/mcp-server"],
      "env": {
        "API_KEY": "value",
        "API_URL": "http://host.docker.internal:3000/api/v1"
      }
    }
  }
}
```

### mcporter Skill

The easiest path to call custom MCP server tools is the bundled `mcporter` skill, which functions as an MCP client/manager CLI.

### Google Workspace MCP

Package: `@presto-ai/google-workspace-mcp`

Capabilities:
- **Gmail**: `gmail.search`, `gmail.get`, `gmail.send`, `gmail.createDraft`
- **Calendar**: `calendar.list`, `calendar.listEvents`, `calendar.createEvent`
- **Drive**: file operations
- **Docs & Sheets**: document/spreadsheet manipulation

Install:
```bash
npx -y @lobehub/market-cli skills install openclaw-skills-google-workspace-mcp
```

Auth: One-time OAuth browser sign-in. Credentials at `~/.config/google-workspace-mcp`.

---

## Plugin System

Plugins are npm packages that register tools exposed to LLMs during agent execution.

### Tool Registration

```typescript
api.registerTool({
  name: "tool_identifier",
  description: "Purpose description",
  parameters: Type.Object({ /* TypeBox schema */ }),
  async execute(_id, params) { /* implementation */ }
});
```

Optional tools (must be explicitly enabled):
```typescript
api.registerTool({ /* config */ }, { optional: true });
```

### Enabling Plugin Tools

```jsonc
{
  "agents": {
    "list": [{
      "tools": {
        "allow": [
          "tool_name",        // Specific tool
          "plugin_id",        // All tools from a plugin
          "group:plugins"     // All plugin tools
        ]
      }
    }]
  }
}
```

### Installing Plugins

```bash
openclaw plugins install <npm-spec>

# Examples
openclaw plugins install @openclaw/matrix         # Matrix channel
openclaw plugins install @icesword760/openclaw-wechat  # WeChat
```

### Plugin Packs

npm packages can bundle multiple plugins:
```json
{
  "name": "@org/hooks-package",
  "openclaw": { "hooks": ["./hooks/hook-a", "./hooks/hook-b"] }
}
```

### Community Plugin Listing Requirements

- Published on npmjs with public GitHub repo
- Setup instructions and documentation
- Active maintainer
- No low-effort wrappers

---

## Custom Skill: Plane API (Example)

For services without an MCP package, create a custom skill:

```
~/.openclaw/workspace/skills/plane/
└── SKILL.md
```

```yaml
---
name: plane
description: Manage Plane project management tickets and pages
tools: [http]
---

# Plane Project Management

API base: `http://host.docker.internal:3003/api/v1`
Auth header: `X-Api-Key: PLANE_API_TOKEN`
Workspace: `akuworkspace`

## Projects
- IAKU — Infrastructure Aku (NixOS, homelab, VPS)
- AWN — Work Notes
...

## Common Operations
- List projects: GET /workspaces/akuworkspace/projects/
- Search: GET /workspaces/akuworkspace/search/?search=QUERY&type=work_item
- Create work item: POST /workspaces/akuworkspace/projects/{id}/work-items/

## Important
- `/api/v1` for work items, projects, states, labels
- `/api/` (NOT /api/v1/) for Pages API
```
