---
id: docs.navigation
summary: User guide for navigating this repository's documentation using the Router and Catalog system.
tags: [docs, navigation, router, catalog, user-guide]
related_files:
  - docs/00_ROUTER.md
  - docs/01_CATALOG.md
  - docs/**
---

# Documentation Navigation Guide

This guide explains how to efficiently navigate this repository's documentation using the **Router** and **Catalog** system.

## Quick Overview

This repository uses a two-tier documentation index:

- **Router** (`docs/00_ROUTER.md`): A compact table for quick topic discovery
- **Catalog** (`docs/01_CATALOG.md`): A comprehensive listing of all modules and documentation

Both are auto-generated and kept in sync with the codebase.

## When to Use What

### Use the Router (`docs/00_ROUTER.md`) when:
- ✅ You know what you're looking for (e.g., "Sway configuration", "Doom Emacs setup")
- ✅ You want to quickly find the relevant documentation
- ✅ You need to discover related code paths
- ✅ You're exploring a specific topic or feature

### Use the Catalog (`docs/01_CATALOG.md`) when:
- ✅ You want to browse all available modules
- ✅ You need to see the complete structure of the repository
- ✅ You're looking for modules by directory structure
- ✅ You want to understand conditional module activation (`lib.mkIf` conditions)

### Browse directly (`docs/`) when:
- ✅ You already know the exact document path
- ✅ You're following links from other documentation
- ✅ You're reading a specific guide from start to finish

## How to Use the Router

The Router is a Markdown table with four columns:

| ID | Summary | Tags | Primary Path |
|----|---------|------|--------------|
| `user-modules.sway-daemon-integration` | Sway session services are managed via systemd... | sway, swayfx, systemd-user | `user/wm/sway/**` |

### Step-by-Step Navigation

1. **Open** `docs/00_ROUTER.md`
2. **Scan** the `Summary` column for your topic
3. **Check** the `Tags` column for relevant keywords
4. **Note** the `ID` (e.g., `user-modules.sway-daemon-integration`)
5. **Find** the documentation file that matches the ID pattern:
   - `user-modules.*` → `docs/user-modules/*.md`
   - `keybindings.*` → `docs/akunito/keybindings.md` or specific guides
   - `docs.*` → `docs/*.md`
6. **Read** the documentation file
7. **Check** the `Primary Path` to find related code files

### Example: Finding Sway Configuration

**Goal**: Learn how Sway session services are managed.

1. Open `docs/00_ROUTER.md`
2. Scan for "Sway" in the Summary or Tags columns
3. Find: `user-modules.sway-daemon-integration` with tags `[sway, swayfx, systemd-user]`
4. Open `docs/user-modules/sway-daemon-integration.md`
5. Check the `Primary Path`: `user/wm/sway/**` to see related code

**Result**: You've found both the documentation and the code location in one step.

### Example: Finding Keybindings

**Goal**: Find Sway keybindings reference.

1. Open `docs/00_ROUTER.md`
2. Search for "keybindings" in Tags or Summary
3. Find: `keybindings.sway` with tags `[sway, swayfx, keybindings, rofi, wayland]`
4. Open the referenced documentation (or check `Primary Path`: `user/wm/sway/swayfx-config.nix`)

### Using Tags for Discovery

Tags help you find related topics:

- **Looking for window manager configs?** Search for tags: `sway`, `xmonad`, `plasma6`, `hyprland`
- **Looking for editor setups?** Search for tags: `emacs`, `doom-emacs`, `editor`
- **Looking for system-level configs?** Search for tags: `systemd`, `nixos`, `hardware`

## How to Use the Catalog

The Catalog (`docs/01_CATALOG.md`) provides a hierarchical view organized by:

- **Flake Architecture**: Top-level flake files
- **Profiles**: Profile-specific configurations
- **System Modules**: System-level modules organized by category
- **User Modules**: User-level modules organized by category
- **Documentation**: All documentation files

### Example: Browsing All User Modules

1. Open `docs/01_CATALOG.md`
2. Scroll to the "User Modules" section
3. Browse by category (App, WM, Style, etc.)
4. Each entry shows:
   - File path
   - Purpose/description
   - Conditional activation (if applicable)

### Example: Finding Module Activation Conditions

1. Open `docs/01_CATALOG.md`
2. Find the module you're interested in
3. Check the "Enabled when:" note to see `lib.mkIf` conditions
4. This tells you when the module is active in your configuration

## Common Navigation Patterns

### Pattern 1: "I want to configure X"

**Example**: "I want to configure Doom Emacs"

1. Open Router → Search for "doom-emacs" or "emacs"
2. Find `user-modules.doom-emacs`
3. Read `docs/user-modules/doom-emacs.md`
4. Check `Primary Path` for code location: `user/app/doom-emacs/**`

### Pattern 2: "Where is the code for X?"

**Example**: "Where is the Sway configuration code?"

1. Open Router → Search for "sway"
2. Find relevant entries (e.g., `user-modules.sway-daemon-integration`)
3. Check `Primary Path` column → `user/wm/sway/**`
4. Navigate to that directory in the codebase

### Pattern 3: "What modules are available?"

**Example**: "What user modules can I enable?"

1. Open Catalog → Scroll to "User Modules"
2. Browse by category (App, WM, Style, etc.)
3. Note the purpose and activation conditions
4. Use Router to find detailed documentation for specific modules

### Pattern 4: "I'm troubleshooting X"

**Example**: "Waybar is slow after relog"

1. Open Router → Search for "waybar" in Tags
2. Find relevant entries (may include incident reports in `future.*` entries)
3. Read the documentation to understand the issue and solution
4. Check `Primary Path` for related code changes

### Pattern 5: "I want to migrate from X to Y"

**Example**: "Migrating from Sway to Hyprland"

1. Open Router → Search for "migration" or "hyprland"
2. Find `user-modules.sway-to-hyprland-migration`
3. Read `docs/user-modules/sway-to-hyprland-migration.md`
4. Check `Primary Path` for migration scripts/code

## Tips for Efficient Navigation

1. **Use your editor's search**: `Ctrl+F` / `Cmd+F` in the Router table to quickly find keywords
2. **Bookmark common entries**: If you frequently reference certain modules, note their IDs
3. **Follow the Primary Path**: The `Primary Path` column shows where related code lives
4. **Check tags**: Tags help you discover related topics you might not have considered
5. **Use both indexes**: Router for quick lookup, Catalog for comprehensive browsing

## Understanding the ID System

Router IDs follow a pattern:

- `user-modules.*` → User-level module documentation in `docs/user-modules/`
- `keybindings.*` → Keybinding references
- `docs.*` → Documentation about the documentation system itself
- `future.*` → Incident reports, migration notes, or future plans

The ID helps you:
- Predict the documentation file location
- Understand the topic category
- Find related entries (same prefix = related topics)

## Keeping Documentation Updated

The Router and Catalog are **auto-generated**. If you:

- Add new documentation files
- Modify existing documentation structure
- Change module organization

Run this to regenerate the indexes:

```sh
python3 scripts/generate_docs_index.py
```

**Note**: The Router and Catalog files have a warning header indicating they're auto-generated. Don't edit them manually.

## Related Documentation

- **[Agent Context System](agent-context.md)**: Technical details about how the Router/Catalog system works (for AI agents and maintainers)
- **[Installation Guide](installation.md)**: Getting started with this repository
- **[Configuration Guide](configuration.md)**: Understanding the configuration structure
- **[README](../README.md)**: Project overview and quick start

## Quick Reference

| Need | Use | File |
|------|-----|------|
| Find specific topic | Router | `docs/00_ROUTER.md` |
| Browse all modules | Catalog | `docs/01_CATALOG.md` |
| Find code location | Router → Primary Path | `docs/00_ROUTER.md` |
| See activation conditions | Catalog | `docs/01_CATALOG.md` |
| Read specific guide | Direct | `docs/user-modules/*.md` |

---

**Remember**: The Router is your fast path to finding documentation. The Catalog is your comprehensive reference. Use both as needed!
