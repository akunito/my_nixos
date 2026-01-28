# Documentation Agent Context

This context applies when working with documentation: `docs/**`, `scripts/generate_docs_index.py`

## Docs Maintenance (Router/Catalog)

### Frontmatter Requirements

When editing or creating major docs, include YAML frontmatter:

```yaml
---
id: unique.stable.identifier
summary: One-line description
tags: [keyword1, keyword2]
related_files:
  - path/to/governed/files/**
---
```

**Fields:**
- `id`: Unique, stable identifier (use dot notation: `module.submodule.feature`)
- `summary`: One-line description (used in Router table)
- `tags`: Array of keywords for filtering
- `related_files`: Array of glob patterns this doc governs (optional; falls back to doc's own path)

### Index Generation

After reorganizing docs or adding major modules/docs, regenerate:

```bash
python3 scripts/generate_docs_index.py
```

This produces:
- `docs/00_ROUTER.md` (routing table)
- `docs/01_CATALOG.md` (full catalog)
- `docs/00_INDEX.md` (shim)

## Router Table Format

The router should be a Markdown table with columns:

`ID | Summary | Tags | Primary Path`

Primary Path should usually be `related_files[0]` (or fallback to the doc path).

## Retrieval Protocol

- Read `docs/00_ROUTER.md` first, choose node(s), then open only the referenced docs/code.
