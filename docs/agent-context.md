---
id: docs.agent-context
summary: How this repo manages AI agent context (Router/Catalog + Cursor rules + AGENTS.md) and a reusable template for other projects.
tags: [cursor, agents, docs, routing, rules]
related_files:
  - docs/00_ROUTER.md
  - docs/01_CATALOG.md
  - scripts/generate_docs_index.py
  - AGENTS.md
  - .cursor/rules/**
---

# Agent context system (Router/Catalog + Rules)

This repo is designed to keep AI context **scoped, fast, and predictable** as documentation grows.

## How it works (quick)

We split “documentation for AI retrieval” into two layers:

- **Router**: `docs/00_ROUTER.md`
  - Small, token-efficient Markdown table.
  - Used to pick the relevant doc node(s) by ID.
- **Catalog**: `docs/01_CATALOG.md`
  - Full listing of modules and docs (paths, summaries, `lib.mkIf` conditions).
  - Used only when you need broad browsing.

Rule application is also split:

- **AGENTS.md**: global repo instructions and the router-first protocol.
- **Cursor Project Rules**: `.cursor/rules/*.mdc` with globs for scoping.
- **Optional nested AGENTS.md**: only in hot spots where locality matters (e.g. `user/wm/sway/AGENTS.md`).

## Router-first protocol (for humans and agents)

Before answering an architectural/implementation question:

1. Read `docs/00_ROUTER.md` and pick the most relevant `ID`(s).
2. Read those doc files.
3. Read the related code under the selected scope.
4. Only then do any search, and keep it scoped.

## Maintaining the Router/Catalog

- Add YAML frontmatter to major docs (especially in `docs/user-modules/`):
  - `id` (unique, stable)
  - `summary` (one line)
  - `tags` (keywords)
  - `related_files` (globs/paths this doc governs)
- If `related_files` is omitted, the router generator will fall back to the doc’s own path.

Regenerate indexes after doc/module changes:

```sh
python3 scripts/generate_docs_index.py
```

Outputs:
- `docs/00_ROUTER.md`
- `docs/01_CATALOG.md`
- `docs/00_INDEX.md` (compat shim)

## Maintenance checklist (recommended)

- After changing docs structure, adding new major docs, or changing frontmatter:
  - Run `python3 scripts/generate_docs_index.py`
- When adding a new “domain rule” for Cursor:
  - Add a **scoped** `.cursor/rules/<name>.mdc` with `globs` so it only applies where relevant
- Keep docs aligned with behavior:
  - Treat `install.sh` as the **source of truth** for installation/sync workflow documentation
  - If docs mention prompts/steps, verify the script actually does them

## Template (copy to other projects)

### Minimal directory layout

```text
AGENTS.md
.cursor/
  rules/
    project-invariants.mdc
    docs-maintenance.mdc
docs/
  00_ROUTER.md
  01_CATALOG.md
  agent-context.md
scripts/
  generate_docs_index.py
```

### Example doc frontmatter

```md
---
id: user-modules.some-feature
summary: One-line description of what this doc covers.
tags: [feature, subsystem, keyword]
related_files:
  - path/that/this/doc/governs/**
  - another/area/*.nix
---
```

### Example router table row

The router should be a Markdown table with:

`ID | Summary | Tags | Primary Path`

Primary Path should usually be `related_files[0]` (or fallback to the doc path).

### Example project rule (Cursor)

Create `.cursor/rules/<name>.mdc` with frontmatter globs and short, scoped guidance.


