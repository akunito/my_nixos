---
paths:
  - "docs/**"
  - "scripts/generate_docs_index.py"
---

# Documentation Rules

## Location Rules

- **README.md**: allowed in project root and any subdirectory (explains folder)
- **All other docs**: MUST be in `docs/` directory
- **NEVER** create .md files outside `docs/` (except README.md)

## Frontmatter (MANDATORY)

Every doc file MUST have YAML frontmatter:

```yaml
---
id: category.subcategory.identifier  # Stable, unique ID (never changes)
summary: One-line description
tags: [tag1, tag2]                   # Lowercase
related_files: [path/**]             # File globs (optional)
date: YYYY-MM-DD
status: draft | published
---
```

## Index Generation

After adding major docs/modules or restructuring, regenerate:

```bash
python3 scripts/generate_docs_index.py
```

This produces `docs/00_ROUTER.md`, `docs/01_CATALOG.md`, and `docs/00_INDEX.md`.

## Key Rules

- **UPDATE existing docs** when adding features -- don't create new files
- **APPEND** to existing sections rather than duplicating content
- **PRESERVE** document IDs -- they are stable identifiers
- Keep individual docs **under 300 lines** (~4,500 tokens)
- If a doc grows beyond 300 lines, split into subdirectory with README.md index

## Documentation During Feature Work

- When adding/modifying a Nix module: check for related doc, update it
- When adding/removing feature flags in `lib/defaults.nix`: update `docs/profile-feature-flags.md`
- After any doc changes: run `python3 scripts/generate_docs_index.py` and stage results

## Encryption

- **Public OK**: Internal IPs, email addresses, service descriptions, interface names
- **MUST encrypt**: Public IPs, WireGuard keys, passwords, API tokens, SNMP strings
- Use `docs/akunito/infrastructure/INFRASTRUCTURE_INTERNAL.md` (already encrypted) or add to `.gitattributes`
