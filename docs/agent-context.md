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

## Migration Guide (for other projects)

This section provides step-by-step instructions for migrating from `.cursorrules` to the Router/Catalog + AGENTS.md system. Use this as a guide when implementing this system in a new project.

### Phase 1: Prepare Documentation with Frontmatter

1. **Identify major documentation files** (especially those that describe features, modules, or subsystems).

2. **Add YAML frontmatter** to each major doc file. Example:

```yaml
---
id: unique.stable.identifier
summary: One-line description of what this doc covers.
tags: [keyword1, keyword2, subsystem]
related_files:
  - path/to/code/this/doc/governs/**
  - another/area/*.ext
---
```

**Frontmatter fields:**
- `id`: Unique, stable identifier (use dot notation: `module.submodule.feature`)
- `summary`: One-line description (used in Router table)
- `tags`: Array of keywords for filtering
- `related_files`: Array of glob patterns or paths this doc governs (optional; falls back to doc's own path)

3. **Start with your most important docs** (user-facing guides, architecture docs, module documentation).

### Phase 2: Create the Router Generator Script

1. **Copy or adapt** `scripts/generate_docs_index.py` from this repo.

2. **Key requirements for the script:**
   - Parse YAML frontmatter from Markdown files
   - Generate `docs/00_ROUTER.md` as a Markdown table with columns: `ID | Summary | Tags | Primary Path`
   - Generate `docs/01_CATALOG.md` as a full listing (detailed catalog)
   - Generate `docs/00_INDEX.md` as a compatibility shim (points to Router + Catalog)

3. **Router table format:**
```markdown
| ID | Summary | Tags | Primary Path |
|----|---------|------|--------------|
| docs.agent-context | How this repo manages AI agent context | cursor, agents, docs | docs/00_ROUTER.md |
```

4. **Test the script:**
```sh
python3 scripts/generate_docs_index.py
```

Verify that `docs/00_ROUTER.md` and `docs/01_CATALOG.md` are generated correctly.

### Phase 3: Create Cursor Project Rules

1. **Create `.cursor/rules/` directory** if it doesn't exist.

2. **Identify rule domains** from your existing `.cursorrules`:
   - Project invariants (e.g., "never use X, always use Y")
   - Documentation maintenance rules
   - Domain-specific rules (e.g., "when editing Sway config, do Z")

3. **Create scoped rule files** (`.mdc` extension):
   - `project-invariants.mdc`: Global project rules
   - `docs-maintenance.mdc`: Rules for maintaining docs/router
   - `<domain>-specific.mdc`: Scoped rules for specific subsystems

4. **Rule file format** (`.cursor/rules/<name>.mdc`):
```markdown
# Rule title

Globs: `*.nix`, `flake.lock`, `**/*.nix`

Content: Your rule content here. Keep it scoped to files matching the globs.
```

**Example:**
```markdown
# NixOS invariants

Globs: `*.nix`, `flake.lock`, `**/*.nix`

- Never suggest editing `/nix/store` or using `nix-env`, `nix-channel`
- Always prefer `flake.nix` and `inputs` as source of truth
- Apply changes via `install.sh`, not manual systemd commands
```

### Phase 4: Create Root AGENTS.md

1. **Create `AGENTS.md`** at the project root.

2. **Include these sections:**
   - **Overview**: Brief description of the project type/architecture
   - **Critical workflow & invariants**: Global rules that apply everywhere
   - **Router-first retrieval protocol**: The core instruction to read Router first
   - **Docs index maintenance**: How to regenerate Router/Catalog
   - **Deprecation note**: Point to AGENTS.md and `.cursor/rules/` instead of `.cursorrules`

3. **Router-first protocol (copy this pattern):**
```markdown
## Router-first retrieval protocol (CRITICAL)

Before answering any architectural/implementation question:

1) Read `docs/00_ROUTER.md` and select the most relevant `ID`(s).
2) Read the documentation file(s) corresponding to those IDs.
3) Only then read the related source files (prefer the `Primary Path` scopes from the Router).
4) Only if still needed: search, but keep it scoped to the selected node's directories.
```

### Phase 5: Migrate from .cursorrules

1. **Read your existing `.cursorrules`** and categorize content:
   - **Global invariants** → Move to `AGENTS.md`
   - **Scoped rules** → Move to `.cursor/rules/<domain>.mdc` with appropriate globs
   - **Documentation references** → Ensure those docs have frontmatter

2. **Replace `.cursorrules`** with a deprecation notice:
```markdown
⚠️ **DEPRECATED**: `.cursorrules` is legacy in this repo.

Use:
- `AGENTS.md` for global agent instructions + router-first retrieval protocol
- `.cursor/rules/*.mdc` for scoped Cursor Project Rules
```

3. **Update any docs** that reference `.cursorrules` to point to `AGENTS.md` or the relevant rule file.

### Phase 6: Optional Nested AGENTS.md

For complex subsystems where locality matters, create nested `AGENTS.md` files:

- Example: `user/wm/sway/AGENTS.md` for Sway-specific guidance
- Keep these minimal; they should reference the main `AGENTS.md` and point to relevant docs

### Phase 7: Update Project Documentation

1. **Add brief references** in main project docs (README.md, installation.md, etc.):
   - Mention the Router/Catalog system
   - Point to `docs/agent-context.md` for details
   - Mention `AGENTS.md` for agent instructions

2. **Regenerate Router/Catalog** after all changes:
```sh
python3 scripts/generate_docs_index.py
```

### Verification Checklist

- [ ] Major docs have YAML frontmatter with `id`, `summary`, `tags`
- [ ] `scripts/generate_docs_index.py` generates Router and Catalog correctly
- [ ] `docs/00_ROUTER.md` is a clean Markdown table
- [ ] `docs/01_CATALOG.md` contains full documentation listing
- [ ] `AGENTS.md` exists with router-first protocol
- [ ] `.cursor/rules/*.mdc` files exist with appropriate globs
- [ ] `.cursorrules` is deprecated (or removed)
- [ ] Main project docs reference the new system
- [ ] Router/Catalog are regenerated and up-to-date

### Maintenance Workflow

After implementing, follow this workflow:

1. **When adding new major docs**: Add frontmatter, then run `python3 scripts/generate_docs_index.py`
2. **When adding new domain rules**: Create `.cursor/rules/<name>.mdc` with scoped globs
3. **When changing behavior**: Update relevant docs, verify frontmatter is still accurate, regenerate Router/Catalog
4. **Periodic check**: Review Router entries to ensure they're still accurate (especially `Primary Path`)

### Troubleshooting

**Router is empty or missing entries:**
- Check that docs have valid YAML frontmatter (no syntax errors)
- Verify the script is scanning the correct directories
- Check that `id` fields are unique

**Rules not applying:**
- Verify glob patterns in `.cursor/rules/*.mdc` match your file structure
- Check that rule files use `.mdc` extension
- Ensure Cursor has indexed the `.cursor/rules/` directory

**Docs out of sync:**
- Run `python3 scripts/generate_docs_index.py` after any doc changes
- Consider adding a pre-commit hook or CI check to enforce regeneration


