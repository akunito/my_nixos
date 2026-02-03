# 🚨 MANDATORY PROTOCOL: Router-First Retrieval

**ALWAYS START HERE** when answering ANY question about this repository's architecture, implementation, configuration, or code location.

## Router-First Protocol (REQUIRED FOR ALL QUERIES)

Before answering **any** architectural, implementation, or "where is X?" question:

1. **FIRST:** Read `docs/00_ROUTER.md` and select the most relevant `ID`(s)
2. **SECOND:** Read the documentation file(s) corresponding to those IDs
3. **THIRD:** Read the related source files (prefer the `Primary Path` from the Router)
4. **ONLY THEN:** If still needed, search (keep it scoped to the selected node's directories)

### Example Queries Requiring Router Check:
- "How is Sway configured?"
- "Where is Doom Emacs setup?"
- "How do I configure X?"
- "What modules are available?"
- "How does Y work in this repo?"

**DO NOT** skip the Router. **DO NOT** search first. **ALWAYS** check Router → Docs → Code.

---

## Overview (for agents)

This is a NixOS flake-based dotfiles repo. Prefer NixOS/Home-Manager modules over imperative commands.

## Critical Workflow & Invariants

- **Immutability**: Never suggest editing `/nix/store` or using `nix-env`, `nix-channel`, `apt`, `yum`
- **Source of truth**: `flake.nix` and its `inputs` define dependencies
- **Application workflow**: Apply changes via `install.sh` (or `aku sync`), not manual systemd enable/start
- **Flake purity**: Prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths inside Nix
- **Secrets management**: Sensitive data (domains, IPs, credentials) is in `secrets/domains.nix` (encrypted with git-crypt). Import via `let secrets = import ../secrets/domains.nix;`

## Home Manager Updates

When modifying Home Manager configuration (user-level modules), apply changes using:

```bash
cd /home/akunito/.dotfiles && ./sync-user.sh
```

This command updates the Home Manager configuration and applies changes without requiring a full system rebuild. Use this for:
- User application configurations (tmux, nixvim, etc.)
- User shell configurations
- User window manager settings
- Any changes in `user/` directory

## Docs Index Maintenance

The router/catalog are auto-generated. After adding major docs/modules or restructuring docs, run:

```bash
python3 scripts/generate_docs_index.py
```

## Deprecation Note

Legacy `.cursorrules` is being replaced by:
- `AGENTS.md` (root-level agent instructions)
- `.agent/rules/*.md` (Antigravity workspace rules)
- `.cursor/rules/*.mdc` (scoped Cursor project rules)
