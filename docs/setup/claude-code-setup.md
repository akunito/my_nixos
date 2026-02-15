---
id: claude-code-setup
summary: Claude Code CLI configuration guide — permissions, hooks, and MCP servers
tags: [claude-code, setup, permissions, hooks, mcp, tooling]
related_files: ["~/.claude/settings.json", "~/.claude.json", ".claude/settings.local.json", "CLAUDE.md"]
---

# Claude Code Setup Guide

Configuration guide for setting up Claude Code CLI on new machines.

## Files Overview

| File | Scope | Purpose |
|------|-------|---------|
| `~/.claude/settings.json` | User-wide (all projects) | Permissions + hooks |
| `~/.claude.json` | Per-project (local) | MCP servers |
| `.claude/settings.local.json` | Per-project (gitignored) | Session-accumulated permissions |
| `CLAUDE.md` | Per-project (committed) | Project instructions for Claude |

## 1. User-Wide Settings (`~/.claude/settings.json`)

Copy this file to `~/.claude/settings.json` on any new machine:

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "WebFetch",
      "WebSearch",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(file *)",
      "Bash(which *)",
      "Bash(echo *)",
      "Bash(env)",
      "Bash(printenv *)",
      "Bash(pwd)",
      "Bash(whoami)",
      "Bash(hostname)",
      "Bash(uname *)",
      "Bash(df *)",
      "Bash(du *)",
      "Bash(free *)",
      "Bash(uptime)",
      "Bash(ps *)",
      "Bash(top -bn1*)",
      "Bash(git status*)",
      "Bash(git log*)",
      "Bash(git diff*)",
      "Bash(git branch*)",
      "Bash(git show*)",
      "Bash(git remote*)",
      "Bash(git tag*)",
      "Bash(git rev-parse*)",
      "Bash(git config --get*)",
      "Bash(git config --list*)",
      "Bash(git stash list*)",
      "Bash(nix eval *)",
      "Bash(nix flake show*)",
      "Bash(nix flake metadata*)",
      "Bash(nix flake info*)",
      "Bash(nix-instantiate --eval*)",
      "Bash(nixos-option *)",
      "Bash(systemctl status *)",
      "Bash(systemctl --user status *)",
      "Bash(systemctl list-units*)",
      "Bash(systemctl list-timers*)",
      "Bash(systemctl is-active*)",
      "Bash(systemctl is-enabled*)",
      "Bash(journalctl *)",
      "Bash(docker ps*)",
      "Bash(docker logs*)",
      "Bash(docker images*)",
      "Bash(docker network ls*)",
      "Bash(docker network inspect*)",
      "Bash(docker volume ls*)",
      "Bash(docker inspect*)",
      "Bash(ip addr*)",
      "Bash(ip link*)",
      "Bash(ip route*)",
      "Bash(ss -*)",
      "Bash(ping *)",
      "Bash(curl -s *)",
      "Bash(curl --silent *)",
      "Bash(dig *)",
      "Bash(nslookup *)",
      "Bash(gh pr list*)",
      "Bash(gh pr view*)",
      "Bash(gh pr status*)",
      "Bash(gh issue list*)",
      "Bash(gh issue view*)",
      "Bash(gh api *)",
      "Bash(gh repo view*)",
      "Bash(tree *)",
      "Bash(find *)",
      "Bash(rg *)",
      "Bash(grep *)",
      "Bash(tailscale status*)",
      "Bash(wg show*)"
    ]
  },
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "notify-send -u normal -t 10000 -i dialog-information 'Claude Code' 'Needs your attention'"
          }
        ]
      }
    ]
  }
}
```

### What's Auto-Allowed

All read-only, non-destructive operations are pre-approved:

- **Dedicated tools**: `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`
- **File inspection**: ls, cat, head, tail, wc, file, tree, find, rg, grep
- **System info**: echo, env, printenv, pwd, whoami, hostname, uname, df, du, free, uptime, ps, top
- **Git read-only**: status, log, diff, branch, show, remote, tag, rev-parse, config --get/--list, stash list
- **Nix read-only**: eval, flake show/metadata/info, nix-instantiate --eval, nixos-option
- **Systemd read-only**: status, list-units, list-timers, is-active, is-enabled, journalctl
- **Docker read-only**: ps, logs, images, network ls/inspect, volume ls, inspect
- **Network diagnostics**: ip addr/link/route, ss, ping, curl -s, dig, nslookup
- **GitHub CLI read-only**: pr list/view/status, issue list/view, api, repo view
- **Infrastructure**: tailscale status, wg show

### What Still Requires Approval

All modifying operations prompt for confirmation:

- File edits (`Edit`, `Write`)
- Git writes (`git commit`, `git push`, `git checkout`, etc.)
- Package management (`nix build`, `nixos-rebuild`, etc.)
- Service control (`systemctl start/stop/restart`)
- Docker mutations (`docker run/stop/rm`)
- Any destructive bash command (`rm`, `mv`, etc.)

## 2. Notification Hook

The `Notification` hook sends a desktop notification whenever Claude Code is waiting for user input. This is useful when running long tasks in a background terminal.

**Requirements**: `notify-send` (from `libnotify`) — included in most desktop NixOS profiles.

**Behavior**: Shows a popup "Claude Code — Needs your attention" for 10 seconds.

**macOS alternative**: Replace the command with:
```json
"command": "osascript -e 'display notification \"Needs your attention\" with title \"Claude Code\"'"
```

## 3. MCP Servers (Optional)

MCP (Model Context Protocol) servers extend Claude Code with external tool integrations.

### Adding an MCP Server

```bash
# HTTP transport (remote services)
claude mcp add --transport http <name> <url>

# stdio transport (local processes)
claude mcp add --transport stdio <name> -- <command> <args>

# List configured servers
claude mcp list

# Remove a server
claude mcp remove <name>
```

### Recommended MCP Servers

| Server | Transport | Use Case | Command |
|--------|-----------|----------|---------|
| GitHub (Copilot) | HTTP | PR/issue management | `claude mcp add --transport http github https://api.githubcopilot.com/mcp/` |
| PostgreSQL | stdio | Database queries | `claude mcp add --transport stdio db -- npx -y @bytebase/dbhub --dsn "postgresql://..."` |
| Playwright | stdio | Browser automation | `claude mcp add --transport stdio playwright -- npx -y @playwright/mcp@latest` |

**Note**: The GitHub Copilot MCP requires a GitHub Copilot subscription. Without it, use `gh` CLI via Bash instead (Claude Code already supports this).

### MCP Configuration Storage

MCP servers are stored in `~/.claude.json` (per-project) or can be shared via `.mcp.json` (committed to repo).

## 4. Setup on a New Machine

```bash
# 1. Install Claude Code
npm install -g @anthropic-ai/claude-code
# or: nix profile install nixpkgs#claude-code

# 2. Create settings directory
mkdir -p ~/.claude

# 3. Copy settings (from this repo or another machine)
cp ~/.dotfiles/docs/setup/claude-code-setup-settings.json ~/.claude/settings.json
# Or just copy the JSON block from section 1 above

# 4. (Optional) Add MCP servers
claude mcp add --transport stdio db -- npx -y @bytebase/dbhub --dsn "postgresql://..."

# 5. Verify
claude --version
```

## 5. Permission Precedence

Rules are evaluated in this order (highest priority first):

1. **Managed settings** (system-level, IT-deployed)
2. **Command line arguments**
3. **Local project** (`.claude/settings.local.json`) — gitignored, accumulated per session
4. **Shared project** (`.claude/settings.json`) — committed
5. **User** (`~/.claude/settings.json`) — what we configured above

A `deny` rule at a higher level overrides an `allow` at a lower level.

## 6. Tips

- **Session permissions**: When Claude asks for permission and you click "Always allow", it saves to `.claude/settings.local.json` (project-local, gitignored). These accumulate over time.
- **Clean up local permissions**: The `.claude/settings.local.json` file can grow large with specific one-off commands. Periodically review and clean it.
- **Interactive config**: Use `/permissions` inside Claude Code to manage rules interactively.
- **Hook debugging**: Hook output (stdout) is added to Claude's context. Use `exit 2` in hook scripts to block an action.
