# Plane Ticket Management — Agent Context

This file is loaded on-demand when agents need detailed Plane integration info.

## Project UUID Table (akunito's projects)

| Identifier | Project Name | UUID | Members |
|------------|-------------|------|---------|
| AINF | AKU Infrastructure | `ea5c0b30-a3ab-4ab3-bd11-a4b47d3d7171` | Diego |
| APER | AKU Personal | `5c7802e2-9a11-46d4-b771-7891164bb5c5` | Diego |
| AWORK | AKU Work Notes | `ec30de69-c749-4506-9441-9690753391f5` | Diego |
| ALEA | AKU Learning | `cb002098-d738-4598-8a95-87affe9cd4d5` | Diego |
| ZEN | Zen Browser Mods | `c3c8a9a5-07c2-428e-8ee8-a81b9f0b6141` | Diego |
| APORT | AKU Portfolio | `e9e0f711-f34a-4a73-938e-fe3c0bf14b19` | Diego, Komi |
| APLANE | AKU Plane APP | `f23dccb9-7945-48bc-b228-908b167552a3` | Diego, Komi |
| LEH | Lefty Home | `490ad552-6cf3-43ca-a1fc-fec9fdf0dd4d` | Diego, Komi |
| LW | Liftcraft | `3a917926-76e4-420f-b729-3dfbb76b4602` | Diego, Komi |
| FIN | Finance | `d1984602-39ab-4e7f-9485-e51620954043` | Diego, Komi |
| IRIN | Irin | `590a3c04-f6fd-4b45-98a8-8ed8c8d27973` | Diego, Aga |
| HOME | Home | `d54ae942-1de9-452a-833d-381807538c60` | Diego, Aga |
| JLE | JL Engine | `09772481-bcf3-4ffb-95e6-3ceddf3563de` | Komi (Diego: 404) |
| INF | Infrastructure & DevOps | `4ec09847-9c12-4a0a-854e-a50ceafa9ea9` | Komi |
| ORB | KOMI - Orbit | `3b54022f-6fa7-48f8-b0c2-5417a49d22e4` | Komi |
| N8N | n8n Workflows | `447e76be-1d4a-4156-889e-69fb3389cf60` | Komi |
| ISG | Inventory Simulator | `5427fcbc-3c8d-4450-946a-8d80c7d13b17` | Komi |

Members (2026-09-11): Diego `794b4ebf-4f96-4532-85e1-24f1b6683fef`, Aga `9ee5907f-308d-4074-927e-57a75f375e6d`, Komi `b24d5e9a-f2f6-4d69-9326-d51c1b7929dd`.
Telegram bot for tickets: `docs/akunito/infrastructure/services/plane-telegram-bot.md` (AINF-380).

**Workspace**: `akuworkspace` | **URL**: https://plane.akunito.com

## MCP Tool Reference

| Tool | Purpose | Key Parameters |
|------|---------|----------------|
| `search_work_items` | Find tickets by keyword | `query`, `project_id` (optional) |
| `list_work_items` | List all items in project | `project_id`, `per_page`, `cursor` |
| `create_work_item` | Create new ticket | `project_id`, `name`, `priority`, `state`, `description_html` |
| `update_work_item` | Change state/fields | `project_id`, `work_item_id`, `state`, `priority` |
| `retrieve_work_item` | Get single item details | `project_id`, `work_item_id` |
| `create_work_item_comment` | Add comment | `project_id`, `work_item_id`, `comment_html` |
| `list_states` | Get state UUIDs for project | `project_id` |
| `list_labels` | Get label UUIDs for project | `project_id` |

All tools are lazy-loaded via `ToolSearch` with `+plane <keyword>`.

### Performance: Avoiding Large Responses

**CRITICAL**: `list_work_items` returns full `description_html` for every item. With 50 items this can consume ~15k tokens. Always use the `fields` parameter to limit response size:

```
# Browsing/searching — lightweight fields only
list_work_items(project_id=<UUID>, per_page=50, fields="id,name,state,sequence_id,priority,created_at")

# Then fetch full details for a specific item
retrieve_work_item(project_id=<UUID>, work_item_id=<UUID>)
```

**Rules:**
- When listing/browsing: always pass `fields="id,name,state,sequence_id,priority,created_at"`
- When searching by name: prefer `search_work_items(query=...)` first (lighter)
- Only omit `fields` when you specifically need descriptions of all items
- Use `per_page=20` instead of 50 when possible

## State Transition Pattern

State UUIDs differ per project. Always resolve at runtime:

```
1. ToolSearch("+plane list states")
2. list_states(project_id=<UUID>)
3. Match by name: "Backlog", "Icebox", "Todo", "In Progress", "In Review", "Done", "Cancelled"
4. Use matched UUID in create_work_item or update_work_item
```

## Ticket Creation Template

```
create_work_item(
  project_id = "<project-uuid>",
  name = "Imperative title (e.g., Fix split DNS circular dependency)",
  priority = "medium",          # urgent | high | medium | low | none
  state = "<state-uuid>",       # resolved via list_states
  description_html = "<p>What: brief description</p><p>Why: context</p><p>Acceptance: criteria</p>"
)
```

## Comment Template (Session Update)

```html
<h3>Session update</h3>
<ul>
  <li><strong>What</strong>: Description of changes made</li>
  <li><strong>Files</strong>: key/files/modified.nix</li>
  <li><strong>Commit</strong>: AINF-42: imperative description</li>
  <li><strong>Next</strong>: Remaining work or follow-up</li>
</ul>
```

## Commit Message Format

```
AINF-42: imperative description of change

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Scope Mapping Guide

| Topic | Project |
|-------|---------|
| NixOS, Sway, Waybar, theming, profiles | AINF |
| Homelab, pfSense, TrueNAS, Docker, VLANs | AINF |
| VPS, monitoring, networking, gaming | AINF |
| Personal tasks, Vaultkeeper finance items | APER |
| Work notes (Schenker, BEAM, Bee360, PowerBI, SQL, AD) | AWORK |
| Azure certs, Kubernetes, interview prep, AI exploration | ALEA |
| Akunito portfolio site | APORT |
| Cross-cutting infra, CI/CD (Komi) | INF |
| Rails workout app | LW |
| CV generation engine | JLE |
| Finance tagger, Vaultkeeper DB, Revolut enrichment, budgeting | FIN |

## Workflow (every session)

1. **Search first**: `search_work_items` for related tickets before starting work
2. **Create or update**: Create ticket if none exists; move existing to "In Progress"
3. **Comment on progress**: Add comments for significant decisions/findings
4. **Close on completion**: Update state to "Done" or "In Review"; add summary comment
5. **Reference in commits**: Include ticket ID (e.g., `AINF-42: fix DNS split`)

## Rules

- **Ticket titles**: Imperative mood, concise (e.g., "Fix split DNS circular dependency")
- **Priority**: `urgent` / `high` / `medium` / `low` / `none`
- **States**: Backlog | Icebox | Todo → In Progress → In Review → Done | Cancelled
- **State IDs differ per project** — always fetch via `list_states` before updating
