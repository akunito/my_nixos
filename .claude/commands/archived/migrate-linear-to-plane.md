# Migrate a Linear project to Plane

Migrate all data from a Linear project into a Plane project using the custom migration script at `scripts/linear-to-plane/`.

## Prerequisites

1. **Linear API token** must be set in `secrets/domains.nix` as `linearApiToken`
2. **Plane API token** must be set in `secrets/domains.nix` as `planeApiToken`
3. Target Plane project must exist (create via Plane UI or MCP)

## Steps

### 1. Update config.py for the target project

Edit `scripts/linear-to-plane/config.py`:
- Set `LW_PROJECT_ID` to the target Plane project UUID
- Set `LINEAR_PROJECT_NAME` to the source Linear project name
- Update `USER_MAP` with Linear email → Plane UUID mappings
- Update `PLANE_STATES` with target project state UUIDs (fetch via `mcp__plane__list_states`)
- Add any name overrides in `map_linear_state()` for non-standard state names

### 2. Run the migration

```bash
cd scripts/linear-to-plane

# Phase 0: Inventory — check what's in Linear
nix-shell --run "python main.py --inventory"

# Phase 1: Export all data to JSON
nix-shell --run "python main.py --export"

# Phase 2: Import everything
nix-shell --run "python main.py --import-all"

# Phase 3: Verify counts match
nix-shell --run "python main.py --verify"

# If any failures, retry them
nix-shell --run "python main.py --retry-failed"
```

### 3. Import milestones as modules

Linear milestones must be imported separately as Plane modules (milestones API not available in Plane CE):
- Use `mcp__plane__create_module` for each milestone
- Use `mcp__plane__add_work_items_to_module` to assign issues
- The `import_overview.py` script handles the project overview page

### 4. Import project overview page

```bash
nix-shell --run "python import_overview.py"
```

## Key API notes

- **Plane work items/labels/comments**: use `/api/v1/` (public API)
- **Plane pages**: use `/api/` (internal API) — the PlaneClient handles this automatically
- **Linear**: GraphQL only, POST to `https://api.linear.app/graphql`
- **Linear GraphQL types**: `project(id:)` uses `String!`, filter fields use `ID!`
- **Plane title limit**: 255 characters — script auto-truncates
- **Comment attribution**: API creates comments as token owner, original author embedded in HTML
- **Rate limits**: Linear ~1500 complexity/min (0.5s delay), Plane ~60 req/min

## State file

`migration_state.json` tracks all migrated entities for resumability. Delete it to start fresh.

## Arguments: $ARGUMENTS
