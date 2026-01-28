# Claude Code Agents

This directory contains context and instructions for Claude Code agents working on this repository.

## Router-First Protocol

All agents MUST follow the router-first retrieval protocol:

1. Read `docs/00_ROUTER.md` and select the most relevant `ID`(s)
2. Read the documentation file(s) corresponding to those IDs
3. Only then read the related source files (prefer the `Primary Path` scopes from the Router)
4. Only if still needed: search, but keep it scoped to the selected node's directories

## Available Agent Contexts

- `nixos-context.md` - NixOS/flake-specific agent instructions
- `docs-context.md` - Documentation maintenance agent instructions
- `sway-context.md` - Sway/Wayland agent instructions
- `gaming-context.md` - Gaming modules (Lutris, Bottles, Vulkan, controllers)

## When to Use

These context files are useful when:
- Spawning sub-agents with the Task tool for specific domains
- Working on complex multi-file changes within a domain
- Needing domain-specific invariants and patterns
