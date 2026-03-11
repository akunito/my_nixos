Run a documentation health check on this repository. Perform these checks and produce a summary table:

1. **Missing frontmatter**: Find `.md` files in `docs/` that lack a `---` YAML frontmatter header. Exclude `README.md`, `00_ROUTER.md`, `01_CATALOG.md`, and `00_INDEX.md` files from this check.

2. **Broken internal links**: Scan active (non-archived) docs for relative `.md` links (e.g., `[text](./path.md)` or `[text](../path.md)`) and verify the targets exist on disk. Report any broken links with the source file and target path.

3. **Active→archived references**: Find active docs (not in `archived/` directories) that link to files inside `archived/` directories. These references should be removed or updated.

4. **Router/Catalog staleness**: Compare modification timestamps — are any docs newer than `docs/00_ROUTER.md`? If so, the Router needs regeneration.

5. **Regenerate if stale**: If the Router is stale, run `python3 scripts/generate_docs_index.py` to regenerate it. Stage the updated `docs/00_ROUTER.md` and `docs/01_CATALOG.md`.

6. **Stale dates**: Flag docs with a `date:` frontmatter field older than 6 months (informational only, not a failure).

Present results in this format:

```
| Check                    | Status    | Count |
|--------------------------|-----------|-------|
| Missing frontmatter      | PASS/FAIL | N     |
| Broken links             | PASS/FAIL | N     |
| Active→archived refs     | PASS/FAIL | N     |
| Router freshness         | OK/STALE  | —     |
| Stale dates (>6mo)       | INFO      | N     |
```

For any FAIL items, list the specific files/links below the table. If the Router was regenerated, mention that the updated files need to be staged.
