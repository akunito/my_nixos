---
id: docs.agent-context
summary: How Claude Code loads context in this repo (rules, reference files, skills).
tags: [claude-code, rules, docs, context]
related_files:
  - CLAUDE.md
  - .claude/rules/**
  - .claude/reference/**
  - scripts/generate_docs_index.py
---

# Claude Code Context System

## How context loads

- **`CLAUDE.md`** (root): Always loaded at startup. Contains universal rules.
- **`.claude/rules/*.md`**: Path-scoped rules with `paths:` YAML frontmatter. Auto-loaded when Claude reads files matching the glob patterns.
- **`.claude/reference/*.md`**: On-demand reference docs. Loaded by skills or when explicitly read.
- **`.claude/commands/*.md`**: Operational skills invoked via `/skill-name`.
- **`.claude/hooks/*.sh`**: Security enforcement scripts.

## Path-scoped rules

| Rule File | Loads When Reading |
|-----------|-------------------|
| `rules/nixos.md` | `**/*.nix`, `flake.*`, `lib/**`, `profiles/**` |
| `rules/deployment.md` | `deploy.sh`, `install.sh`, `deploy-servers*.conf` |
| `rules/darwin.md` | `system/darwin/**`, `profiles/darwin/**`, `profiles/MACBOOK-*` |
| `rules/gaming.md` | `user/app/games/**`, `system/app/proton.nix`, etc. |
| `rules/sway.md` | `user/wm/sway/**`, `user/wm/waybar/**` |
| `rules/docs.md` | `docs/**`, `scripts/generate_docs_index.py` |

## Reference files

| File | Purpose |
|------|---------|
| `reference/infrastructure-registry.md` | Nodes, services, Docker containers, local projects, skills |
| `reference/plane-context.md` | Plane MCP integration, project UUIDs, workflow |

## Index generation

After adding major docs or restructuring:

```sh
python3 scripts/generate_docs_index.py
```

## Frontmatter

Every doc should have YAML frontmatter with `id`, `summary`, `tags`, and optionally `related_files`. The index generator uses these.
