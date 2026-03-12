---
id: setup.plane-integration
summary: Plane project management MCP integration for Claude Code workflows
tags: [plane, mcp, project-management, claude-code, setup, tooling]
related_files: [".claude/agents/plane-context.md", "CLAUDE.md"]
date: 2026-03-11
status: published
---

# Plane Integration for Claude Code

## Overview

This repository uses a self-hosted [Plane](https://plane.so) instance for project/ticket management, integrated into Claude Code via MCP (Model Context Protocol).

- **Instance**: https://plane.akunito.com
- **Workspace**: `akuworkspace`
- **MCP Server**: Configured in `~/.claude/settings.json` under `mcpServers.plane`

## Workspace Structure

### Projects (akunito)

| Identifier | Name | Scope |
|------------|------|-------|
| AINF | AKU - Infrastructure | NixOS desktop/WM, homelab, networking, pfSense, TrueNAS, VPS, Docker, VLANs, monitoring, theming, gaming, profiles |
| APER | AKU - Personal | Vaultkeeper finance items, personal tasks |
| AWORK | AKU - Work Notes | Work documentation (Schenker, BEAM, Bee360, PowerBI, SQL, AD, ServiceNow) |
| ALEA | AKU - Learning | Certifications, interview prep, AI exploration |
| APORT | AKU - Portfolio | Akunito's portfolio site |

### Projects (shared/other)

| Identifier | Name | Scope |
|------------|------|-------|
| INF | Infrastructure & DevOps | Komi cross-cutting infra, CI/CD |
| LW | Liftcraft | Rails training app |
| JLE | JL Engine | CV generation engine |

## Workflow States

All projects use 7 states (UUIDs differ per project — always fetch via `list_states`):

| State | Group | Meaning |
|-------|-------|---------|
| Backlog | backlog | Default state for new items |
| Icebox | backlog | Parked for later, low priority |
| Todo | unstarted | Ready to start |
| In Progress | started | Actively being worked on |
| In Review | started | Waiting for review or testing |
| Done | completed | Finished |
| Cancelled | cancelled | Won't do |

## MCP Tools (Whitelisted)

These Plane MCP tools are available via `ToolSearch("+plane <keyword>")`:

| Tool | Description |
|------|-------------|
| `search_work_items` | Search tickets by keyword across workspace or within project |
| `list_work_items` | List all work items in a project (paginated) |
| `create_work_item` | Create a new ticket |
| `update_work_item` | Update ticket fields (state, priority, assignees, etc.) |
| `retrieve_work_item` | Get full details of a single work item |
| `create_work_item_comment` | Add a comment to a work item |
| `list_states` | Get state UUIDs for a project (required before state updates) |
| `list_labels` | Get label UUIDs for a project |

## Token Efficiency Design

The integration uses a three-tier approach to minimize always-on token cost:

| Tier | File | Tokens | When Loaded |
|------|------|--------|-------------|
| 1 | CLAUDE.md (Plane section) | ~200 | Every session |
| 2 | `.claude/agents/plane-context.md` | ~800 | On-demand (agent context) |
| 3 | This file (`docs/setup/plane-integration.md`) | 0 | Manual lookup only |

MCP tool definitions (~200 each) are lazy-loaded via `ToolSearch` only when needed.

## Troubleshooting

### MCP connection issues
- Verify the Plane MCP server is running: check `~/.claude/settings.json` for the `plane` entry
- Ensure the API key is valid and has workspace admin permissions
- Test with: `ToolSearch("+plane list projects")` then `list_projects()`

### State UUID mismatch
- State UUIDs are project-specific — never hardcode them
- Always call `list_states(project_id=<UUID>)` before any state update
- Match states by `name` field, not by UUID

### Project not found
- Use `list_projects()` to get current project list and UUIDs
- Project identifiers (AINF, AWORK, etc.) are for human reference; API calls use UUIDs

## History

- **2026-02-26**: Created. Merged HLN (Homelab & Networking) + NXD (NixOS Desktop & WM) into IAKU (Infrastructure Aku).
- **2026-03-10**: Renamed projects: IAKU→AINF, AWN→AWORK, CAL→ALEA, AKU→APORT. Added APER (AKU - Personal).
