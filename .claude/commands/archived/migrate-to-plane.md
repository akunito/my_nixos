# Migrate external service data to Plane

General-purpose skill for migrating data from external project management tools into Plane. Covers patterns proven in production migrations.

## Available migration scripts

| Source | Script | Status |
|--------|--------|--------|
| Obsidian vault | `scripts/obsidian-to-plane/` | Production (613 pages, 47 work items) |
| Linear | `scripts/linear-to-plane/` | Production (92 issues, 76 comments, 8 modules) |

## Common patterns across all migrations

### 1. Plane API endpoints
- **Public API (v1)**: `https://plane.akunito.com/api/v1/workspaces/akuworkspace/projects/{id}/...`
  - Work items (issues), labels, comments, links, states, modules, cycles
- **Internal API**: `https://plane.akunito.com/api/workspaces/akuworkspace/projects/{id}/pages/`
  - Pages only — the VPS `start-override.sh` was patched to expose this

### 2. Auth
- Header: `X-Api-Key: {token}` (token from `secrets/domains.nix` → `planeApiToken`)

### 3. Rate limiting
- Plane: ~60 req/min, use 0.5s delay + exponential backoff on 429
- Always implement resumable state via JSON file

### 4. Content conversion
- Markdown → HTML via Python `markdown` library with extensions: `tables`, `fenced_code`, `nl2br`
- Embed attribution metadata in HTML for items created via API (comments, pages)

### 5. Secrets
- All API tokens in `secrets/domains.nix` (git-crypt encrypted)
- Read via regex: `re.search(r'tokenName\s*=\s*"([^"]+)"', content)`

### 6. Nix dev environment
```nix
# shell.nix
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    (python313.withPackages (ps: with ps; [ markdown beautifulsoup4 requests ]))
  ];
}
```

### 7. Plane entity limits
- Work item name: max 255 characters
- Link title: max 255 characters
- Duplicate link URLs rejected (400)

### 8. Features that need manual enable
- Modules: `mcp__plane__update_project(project_id, module_view=true)`
- Milestones: not available via API in Plane CE — use modules instead

## Arguments: $ARGUMENTS
