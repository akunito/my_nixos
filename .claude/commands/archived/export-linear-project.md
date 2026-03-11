# Export a Linear project to JSON

Export all data from a Linear project (issues, comments, labels, milestones, cycles, documents, workflow states) to a local JSON file for backup or migration purposes.

## Prerequisites

- `linearApiToken` set in `secrets/domains.nix`

## Usage

```bash
cd scripts/linear-to-plane

# First check what's available
nix-shell --run "python main.py --inventory"

# Then export everything
nix-shell --run "python main.py --export"
```

## Output

Creates `scripts/linear-to-plane/linear_export.json` containing:
- All issues with full details (state, priority, assignee, labels, description, attachments, parent/children)
- All comments per issue with author and timestamps
- Workflow states for the team
- Labels with colors
- Project milestones
- Cycles with associated issues
- Documents with content
- Workspace users

## Customization

Edit `config.py` to change:
- `LINEAR_PROJECT_NAME` — project to export
- `LINEAR_TEAM_KEY` — team filter

The export is a complete snapshot that can be used for:
- Migration to Plane (via `--import-all`)
- Backup/archival
- Data analysis
- Migration to other tools

## Arguments: $ARGUMENTS
