---
name: sync-claude-config
description: Sync Claude Code config (settings, commands, skills, plugins, plans, CLAUDE.md) between DESK and LAPTOP_X13 via SSH without overwriting per-machine session state
allowed-tools: Bash, AskUserQuestion
---

# Sync Claude Code Config

Syncs the user-level `~/.claude/` config between machines using rsync. Preserves per-machine session state (`projects/`, `sessions/`, `tasks/`, `todos/`, `history.jsonl`, `shell-snapshots/`, `file-history/`, `backups/`) and never touches the nix-managed `mcp-env` symlink or the local `.credentials.json`.

## Usage

```bash
/sync-claude-config [direction]
```

## Parameters

- `direction` (optional): `desk-to-laptop` (default) or `laptop-to-desk`

## Prerequisites

- Both machines reachable over SSH (LAN or Tailscale)
- `~/.dotfiles/scripts/sync-claude-settings.sh` available (used to push `settings.json` with the desktop notify-send rewrite)
- Take note: the destination's session history is **preserved** — only config-class paths are overwritten

## Machine Details

| Machine | User | LAN IPs | Tailscale | SSH port |
|---------|------|---------|-----------|----------|
| DESK | akunito | 192.168.8.96 | nixosaku | 22 |
| LAPTOP_X13 | akunito | 192.168.8.92, 192.168.8.91 | 100.64.0.8 | 22 |

## What syncs

| Path | Action | Notes |
|------|--------|-------|
| `settings.json` | push (overwrite) | via `~/.dotfiles/scripts/sync-claude-settings.sh` (rewrites `notify-send` for desktop targets) |
| `commands/` | push with `--delete` | source-canonical |
| `skills/` | push with `--delete` | source-canonical |
| `plugins/` | push with `--delete` | source-canonical (3-5 MB; loses any destination-only plugin state by design) |
| `CLAUDE.md` | push if present | global user instructions |
| `plans/` | push with `--ignore-existing` | adds missing plans, **never overwrites** existing ones |

## What is NEVER touched

- `projects/`, `sessions/`, `tasks/`, `todos/`, `history.jsonl`, `shell-snapshots/`, `file-history/`, `backups/` — per-machine session state
- `.credentials.json` — destination's own Claude login
- `mcp-env` — nix-managed symlink to `/nix/store/…-home-manager-files/.claude/mcp-env`; refreshed by home-manager on the destination, not by this skill
- `telemetry/`, `debug/`, `cache/`, `paste-cache/`, `session-env/`, `stats-cache.json`, `settings.json.bak` — ephemeral

## Implementation

When invoked:

1. **Determine direction** from argument (default: `desk-to-laptop`).
2. **Probe IPs** for the target — try LAN first, fall back to Tailscale. For LAPTOP_X13: `192.168.8.92` → `192.168.8.91` → `100.64.0.8`. For DESK: `192.168.8.96`.
3. **Ask for confirmation** before any write step (use `AskUserQuestion`).
4. **Dry-run preview** of `commands/`, `skills/`, `plugins/`, and `plans/`. Show the file lists.
5. **Snapshot the destination** to `~/.claude.pre-migrate-$(date +%Y%m%d-%H%M%S).tar.zst` (kept in `$HOME` on the destination for rollback).
6. **Push `settings.json`** by delegating to `~/.dotfiles/scripts/sync-claude-settings.sh` with the appropriate target (`laptop` or `desk` — extend the script if syncing TO desk).
7. **Push `commands/`, `skills/`, `plugins/`** with `rsync -avz --delete`.
8. **Push `CLAUDE.md`** if present at source.
9. **Merge `plans/`** with `rsync -avz --ignore-existing`.
10. **Verify** on the destination — print counts (`commands`, `skills`, `plugins` subdirs, `plans`), `wc -l settings.json`, `wc -l history.jsonl` (should be unchanged), `ls projects/ | wc -l` (should be unchanged), `ls todos/ | wc -l` (should be unchanged), `readlink ~/.claude/mcp-env`, and `cat ~/.claude/mcp-env | cut -d= -f1`.

### DESK → LAPTOP_X13

```bash
TARGET=akunito@100.64.0.8   # use 192.168.8.92 / .91 if reachable

# 1. Dry-run preview
rsync -avzn --delete ~/.claude/commands/ ${TARGET}:~/.claude/commands/
rsync -avzn --delete ~/.claude/skills/   ${TARGET}:~/.claude/skills/
rsync -avzn --delete ~/.claude/plugins/  ${TARGET}:~/.claude/plugins/
rsync -avzn --ignore-existing ~/.claude/plans/ ${TARGET}:~/.claude/plans/

# 2. Snapshot destination
ssh -A ${TARGET} "tar --zstd -cf ~/.claude.pre-migrate-$(date +%Y%m%d-%H%M%S).tar.zst -C ~ .claude"

# 3. Push settings.json (delegated)
~/.dotfiles/scripts/sync-claude-settings.sh laptop

# 4. Push canonical config
rsync -avz --delete ~/.claude/commands/ ${TARGET}:~/.claude/commands/
rsync -avz --delete ~/.claude/skills/   ${TARGET}:~/.claude/skills/
rsync -avz --delete ~/.claude/plugins/  ${TARGET}:~/.claude/plugins/

# 5. Push CLAUDE.md if present
[ -f ~/.claude/CLAUDE.md ] && rsync -avz ~/.claude/CLAUDE.md ${TARGET}:~/.claude/CLAUDE.md

# 6. Merge plans/
rsync -avz --ignore-existing ~/.claude/plans/ ${TARGET}:~/.claude/plans/

# 7. Verify
ssh -A ${TARGET} 'echo commands=$(ls ~/.claude/commands/|wc -l); \
                  echo skills=$(ls ~/.claude/skills/|wc -l); \
                  echo plugins_subdirs=$(find ~/.claude/plugins -maxdepth 3 -type d|wc -l); \
                  echo settings_lines=$(wc -l <~/.claude/settings.json); \
                  echo plans=$(ls ~/.claude/plans/|wc -l); \
                  echo history_lines=$(wc -l <~/.claude/history.jsonl); \
                  echo projects=$(ls ~/.claude/projects/|wc -l); \
                  echo todos=$(ls ~/.claude/todos/|wc -l); \
                  echo mcp_env_target=$(readlink ~/.claude/mcp-env); \
                  echo mcp_env_keys=$(cat ~/.claude/mcp-env | grep -c "^[A-Z_]*=")'
```

### LAPTOP_X13 → DESK

Same shape, swap source/target. Note: `sync-claude-settings.sh` only ships `laptop`/`vps`/`all` targets today — extend it before using `laptop-to-desk` direction if you want the notify-send rewrite to be skipped for DESK (DESK is already the desktop context, so a plain `scp` is sufficient).

## mcp-env note

`~/.claude/mcp-env` is a symlink into `/nix/store`, generated by home-manager from `user/app/claude-code/claude-code.nix`. Both DESK and LAPTOP_X13 already wire all MCP keys (`perplexityApiKey`, `planeApiToken`, `planeApiUrl`, `planeWorkspaceSlug`, `grafanaMcpToken`, `grafanaMcpUrl`, `dbClaudeReadonlyConnStr`, `n8nMcpApiKey`, `n8nMcpUrl`) in their profile configs. To refresh:

```bash
ssh -A ${TARGET} "cd ~/.dotfiles && git fetch origin && git reset --hard origin/main && ./sync-user.sh"
```

Or from DESK: `./deploy.sh --profile LAPTOP_X13` (full system + user rebuild).

## Rollback

The pre-migration snapshot lives at `~/.claude.pre-migrate-<timestamp>.tar.zst` on the destination. To restore:

```bash
ssh -A ${TARGET} "rm -rf ~/.claude && tar --zstd -xf ~/.claude.pre-migrate-<timestamp>.tar.zst -C ~"
```

Delete the snapshot manually after a few days of stable operation.

## Notes

- `commands/` and `skills/` use `--delete`: any file present only on the destination is removed. This is intentional — the source is canonical for config.
- `plans/` uses `--ignore-existing`: protects in-progress destination plans (this is the only path that gets merge semantics).
- `plugins/` uses `--delete` per user request — installed plugin state on the destination is replaced with the source's set.
- Project-level skills under `<repo>/.claude/commands/` are **not** affected by this skill; they ride along with `git pull` of the dotfiles repo.
- Backup destination of the snapshot is `$HOME` on the target — does not consume Nextcloud/NAS quota.
