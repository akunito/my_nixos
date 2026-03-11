---
id: docs.agent-context
summary: How AI agents retrieve context in this repo (Router/Catalog protocol, index regeneration, key files).
tags: [cursor, claude-code, agents, docs, routing, rules]
related_files:
  - docs/00_ROUTER.md
  - docs/01_CATALOG.md
  - scripts/generate_docs_index.py
  - AGENTS.md
  - CLAUDE.md
  - .claude/agents/**
---

# Agent Context System

## Router-first protocol

Before answering an architectural/implementation question:

1. Read `docs/00_ROUTER.md` and pick the most relevant `ID`(s).
2. Read those doc files.
3. Read the related code under the selected scope.
4. Only then do any search, and keep it scoped.

## Regenerating indexes

After adding major docs, restructuring docs, or changing frontmatter:

```sh
python3 scripts/generate_docs_index.py
```

This updates `docs/00_ROUTER.md` and `docs/01_CATALOG.md`.

## Key files

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Main project instructions for Claude Code (auto-loaded) |
| `AGENTS.md` | Global repo instructions for Cursor agents |
| `.claude/agents/` | Domain-specific agent contexts (plane, nixos, docs) |
| `.cursor/rules/*.mdc` | Scoped Cursor project rules with globs |
| `docs/00_ROUTER.md` | Quick-lookup table by ID/tags |
| `docs/01_CATALOG.md` | Full documentation listing |

## Frontmatter

Every major doc should have YAML frontmatter with `id`, `summary`, `tags`, and optionally `related_files` (globs). The router generator uses these to build the index.
