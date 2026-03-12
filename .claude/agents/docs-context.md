# Documentation Agent Context

This context applies when working with documentation: `docs/**`, `scripts/generate_docs_index.py`

## Documentation Location (STRICT)

**README.md Exception (ALLOWED):**
- README.md in project root - project overview
- README.md in ANY subdirectory - explains what that folder contains

**All Other Documentation (MUST be in docs/):**
- **NEVER** create other .md files in project root or subdirectories
- **ALWAYS** use `docs/` directory for comprehensive documentation
- **ALWAYS** follow router/catalog system (00_ROUTER.md + 01_CATALOG.md)

## Documentation Structure (REQUIRED)

```
<project>/docs/
├── 00_ROUTER.md          # Navigation index (REQUIRED)
├── 01_CATALOG.md         # Metadata catalog (REQUIRED)
├── ARCHITECTURE.md       # System design
├── ENVIRONMENT_SETUP.md  # Development setup
├── DEPLOYMENT.md         # Deployment procedures
├── API.md                # API reference (if applicable)
├── TROUBLESHOOTING.md    # Common issues
```

Generator script: `scripts/generate_docs_index.py`

## Frontmatter (MANDATORY)

Every documentation file MUST have YAML frontmatter:

```yaml
---
id: category.subcategory.identifier  # Stable, unique ID
summary: One-line description         # Concise summary
tags: [tag1, tag2]                   # Lowercase tags
related_files: [path/**]             # File globs (optional)
date: YYYY-MM-DD                     # ISO date
status: draft | published            # Document status
---
```

## Index Generation

After reorganizing docs or adding major modules/docs, regenerate:

```bash
python3 scripts/generate_docs_index.py
```

This produces:
- `docs/00_ROUTER.md` (routing table)
- `docs/01_CATALOG.md` (full catalog)
- `docs/00_INDEX.md` (shim)

## Incremental Updates (CRITICAL)

- **UPDATE existing docs** when adding features/changes - don't create new files
- **APPEND** to existing sections rather than duplicating content
- **REGENERATE** router after changes: `python3 scripts/generate_docs_index.py`
- **PRESERVE** document IDs - they are stable identifiers and NEVER change

## Document Size (RECOMMENDED)

- Keep individual docs **under 300 lines** (~4,500 tokens)
- If a doc grows beyond 300 lines, split into topic-specific files in a subdirectory
- Create a `README.md` index in the subdirectory that links to each sub-doc
- Sub-doc IDs follow `<parent-id>.<subtopic>` naming (e.g., `scripts.installation`)

## Documentation Maintenance (during feature work)

- **When adding/modifying a Nix module**: Check if a related doc exists (use Router or `related_files` frontmatter). Update it.
- **When adding/removing feature flags** in `lib/defaults.nix`: Update `docs/profile-feature-flags.md`.
- **After any doc changes**: Run `python3 scripts/generate_docs_index.py` and stage the regenerated files.
- **New .md files**: Must have YAML frontmatter (`id`, `summary`, `tags`, `date`, `status`). Must be in `docs/`.
- **Periodic check**: Run `/docs-health` to find broken links and stale docs.

## Documentation Encryption

- **Public docs are OK for**: Internal IPs (192.168.x.x, 172.x.x.x, 10.x.x.x), email addresses, service descriptions, interface names
- **MUST encrypt**: Public IPs, WireGuard keys, passwords, API tokens, SNMP community strings
- **Encryption methods**:
  1. Add sensitive content to `docs/akunito/infrastructure/INFRASTRUCTURE_INTERNAL.md` (already encrypted)
  2. Or add new file to `.gitattributes` with `filter=git-crypt diff=git-crypt`
- **Template pattern**: For encrypted docs with complex structure, create a `.template` version showing structure without real values
- **Verify encryption**: Run `git-crypt status` to confirm files are encrypted before pushing

## Router Table Format

The router should be a Markdown table with columns:

`ID | Summary | Tags | Primary Path`

Primary Path should usually be `related_files[0]` (or fallback to the doc path).

## Retrieval Protocol

- Read `docs/00_ROUTER.md` first, choose node(s), then open only the referenced docs/code.

## Pre-Commit Checklist (docs)

When committing changes that include `.md` files:
1. Run `python3 scripts/generate_docs_index.py`
2. Stage regenerated `docs/00_ROUTER.md` and `docs/01_CATALOG.md`
3. Include them in the same commit as the doc changes
4. Delete `docs/00_INDEX.md` if regenerated (legacy shim, not needed)
