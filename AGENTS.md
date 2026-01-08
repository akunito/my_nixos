## Overview (for agents)

This is a NixOS flake-based dotfiles repo. Prefer NixOS/Home-Manager modules over imperative commands.

## Critical workflow & invariants

- **Immutability**: never suggest editing `/nix/store` or using `nix-env`, `nix-channel`, `apt`, `yum`.
- **Source of truth**: `flake.nix` and its `inputs` define dependencies.
- **Application workflow**: apply changes via `install.sh` (or `phoenix sync`), not manual systemd enable/start.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths inside Nix.

## Router-first retrieval protocol (CRITICAL)

Before answering any architectural or implementation question:

1) Read `docs/00_ROUTER.md` and select the most relevant `ID`(s).
2) Read the documentation file(s) corresponding to those IDs.
3) Only then read the related source files (prefer the `Primary Path` scopes from the Router).
4) Only if still needed: search, but keep it scoped to the selected node’s directories.

## Docs index maintenance

- The router/catalog are auto-generated. After adding major docs/modules or restructuring docs, run:
  - `python3 scripts/generate_docs_index.py`

## Deprecation note

Legacy `.cursorrules` is being replaced by:
- `AGENTS.md` (this file)
- `.cursor/rules/*.mdc` (scoped project rules)

