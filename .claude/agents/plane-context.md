# Plane Ticket Management — Agent Context

This file is loaded on-demand when agents need detailed Plane integration info.

## Project UUID Table

| Identifier | Project Name | UUID |
|------------|-------------|------|
| IAKU | Infrastructure Aku | `ea5c0b30-a3ab-4ab3-bd11-a4b47d3d7171` |
| AWN | AKU - Work Notes | `ec30de69-c749-4506-9441-9690753391f5` |
| CAL | Career & Learning | `cb002098-d738-4598-8a95-87affe9cd4d5` |
| INF | Infrastructure & DevOps | `4ec09847-9c12-4a0a-854e-a50ceafa9ea9` |
| LW | Liftcraft | `3a917926-76e4-420f-b729-3dfbb76b4602` |
| JLE | JL Engine | `09772481-bcf3-4ffb-95e6-3ceddf3563de` |
| PWS | KOMI Portfolio | `236867e0-a4ab-4aea-9a22-dc28cec009b6` |
| AKU | AKU Portfolio | `e9e0f711-f34a-4a73-938e-fe3c0bf14b19` |
| ISG | Inventory Simulator | `5427fcbc-3c8d-4450-946a-8d80c7d13b17` |
| N8N | n8n Workflows | `447e76be-1d4a-4156-889e-69fb3389cf60` |

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
  <li><strong>Commit</strong>: IAKU-42: imperative description</li>
  <li><strong>Next</strong>: Remaining work or follow-up</li>
</ul>
```

## Commit Message Format

```
IAKU-42: imperative description of change

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Scope Mapping Guide

| Topic | Project |
|-------|---------|
| NixOS, Sway, Waybar, theming, profiles | IAKU |
| Homelab, pfSense, TrueNAS, Docker, VLANs | IAKU |
| VPS, monitoring, networking, gaming | IAKU |
| Work notes (Schenker, BEAM, Bee360, PowerBI, SQL, AD) | AWN |
| Azure certs, Kubernetes, interview prep, AI exploration | CAL |
| Cross-cutting infra, CI/CD (Komi) | INF |
| Rails workout app | LW |
| CV generation engine | JLE |
| Komi portfolio site | PWS |
| Akunito portfolio site | AKU |
| Inventory simulator game | ISG |
| n8n automation workflows | N8N |
