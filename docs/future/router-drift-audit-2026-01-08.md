---
id: future.router-drift-audit-2026-01-08
summary: Audit findings for Router/Catalog doc drift vs current repo state (install.sh + Sway daemon system).
tags: [router, catalog, audit, docs, drift]
related_files:
  - docs/00_ROUTER.md
  - docs/01_CATALOG.md
  - scripts/generate_docs_index.py
---

# Router/Catalog drift audit (2026-01-08)

## Router row verification

All current router rows point at existing primary paths:

| Router ID | Doc | Primary Path exists? | Status |
|---|---|---:|---|
| `user-modules.doom-emacs` | `docs/user-modules/doom-emacs.md` | ✅ | OK |
| `user-modules.lmstudio` | `docs/user-modules/lmstudio.md` | ✅ | OK |
| `user-modules.picom` | `docs/user-modules/picom.md` | ✅ | OK |
| `user-modules.plasma6` | `docs/user-modules/plasma6.md` | ✅ | **Doc drift** (see below) |
| `user-modules.ranger` | `docs/user-modules/ranger.md` | ✅ | OK |
| `user-modules.sway-daemon-integration` | `docs/user-modules/sway-daemon-integration.md` | ✅ | **Deprecated architecture** (see below) |
| `user-modules.sway-to-hyprland-migration` | `docs/user-modules/sway-to-hyprland-migration.md` | ✅ | OK |
| `user-modules.xmonad` | `docs/user-modules/xmonad.md` | ✅ | OK |

## Drift issues found

### 1) Sway daemon-manager legacy still referenced (must be removed)

Your intended state is “official/native NixOS/Home-Manager approach only”, but these files currently reference legacy daemon-manager:

- `docs/user-modules/sway-daemon-integration.md` (large legacy section, frontmatter summary mentions legacy fallback)
- `.cursor/rules/sway-daemon-integration.mdc` (mentions legacy daemon-manager)
- `user/wm/sway/AGENTS.md` (mentions legacy daemon-manager)
- `user/wm/sway/default.nix` (still contains daemon-manager code paths)

### 2) Plasma6 doc claims install.sh prompts for export (not true)

`docs/user-modules/plasma6.md` says `install.sh` prompts to export Plasma dotfiles, but `install.sh` contains no plasma/export logic.

### 3) Docs still reference legacy `.cursorrules` (needs updating)

`docs/configuration.md` references `.cursorrules` as the canonical location for Nix bash interpolation guidance; `.cursorrules` is deprecated in this repo.


