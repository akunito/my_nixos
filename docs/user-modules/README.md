---
id: user-modules
summary: Complete reference for user-level Home Manager modules — applications, shells, window managers, theming, and packages
tags: [user-modules, home-manager, configuration, modules]
related_files: [user/**/*.nix]
date: 2026-02-15
status: published
---

# User Modules Guide

Complete reference for user-level Home Manager modules in this configuration.

## Overview

User modules are located in the `user/` directory and provide user-level configuration managed by Home Manager. They are imported in profile `home.nix` files and receive variables via `extraSpecialArgs`.

### Module Structure

```nix
{ lib, userSettings, pkgs, systemSettings, ... }:
{
  programs.example.enable = true;
}
```

## Detailed Documentation

Each module has its own doc in this directory:

### Application Modules (`user/app/`)

| Doc | Module |
|-----|--------|
| [doom-emacs.md](doom-emacs.md) | Doom Emacs setup, Org Mode, Magit, Stylix themes |
| [gaming.md](gaming.md) | Lutris/Bottles wrappers, Vulkan/RDNA 4 fixes, Wine |
| [lmstudio.md](lmstudio.md) | LM Studio with MCP server support |
| [nixvim.md](nixvim.md) | NixVim (Cursor IDE-like Neovim with AI features) |
| [nixvim-beginners-guide.md](nixvim-beginners-guide.md) | Beginner's guide to NixVim and Avante |
| [ollama.md](ollama.md) | Ollama local LLM server, RDNA4 Vulkan workaround |
| [ranger.md](ranger.md) | Ranger TUI file manager |
| [tmux.md](tmux.md) | Tmux multiplexer with SSH smart launcher |
| [tmux-persistent-sessions.md](tmux-persistent-sessions.md) | Tmux persistent sessions across reboots |
| [db-credentials.md](db-credentials.md) | Database credential files (pgpass, my.cnf, redis) |
| [windows11-qxl-setup.md](windows11-qxl-setup.md) | Windows 11 QXL/SPICE VM setup |

### Window Manager Modules (`user/wm/`)

| Doc | Module |
|-----|--------|
| [sway-daemon-integration.md](sway-daemon-integration.md) | Sway session services via systemd --user |
| [sway-output-layout-kanshi.md](sway-output-layout-kanshi.md) | Sway output management with kanshi + swaysome |
| [sway-to-hyprland-migration.md](sway-to-hyprland-migration.md) | SwayFX to Hyprland migration guide |
| [swaybgplus.md](swaybgplus.md) | SwayBG+ GUI multi-monitor wallpapers |
| [swww.md](swww.md) | swww wallpaper daemon |
| [waypaper.md](waypaper.md) | Waypaper GUI wallpaper manager |
| [rofi.md](rofi.md) | Rofi launcher (Stylix-themed, combi mode) |
| [plasma6.md](plasma6.md) | Plasma 6 config integration |
| [xmonad.md](xmonad.md) | XMonad tiling WM |
| [picom.md](picom.md) | Picom X11 compositor |

### Style & Theming

| Doc | Module |
|-----|--------|
| [stylix-containment.md](stylix-containment.md) | Stylix theming containment (Sway vs Plasma 6) |
| [unified-dark-theme-portals.md](unified-dark-theme-portals.md) | Dark theme portal integration |

### Shell & System

| Doc | Module |
|-----|--------|
| [shell-multiline-input.md](shell-multiline-input.md) | Multi-line shell input with Shift+Enter |
| [thunderbolt-dock.md](thunderbolt-dock.md) | Thunderbolt dock setup |

## Using Modules

### Importing in home.nix

```nix
imports = [
  ../../user/app/git/git.nix
  ../../user/wm/plasma6/plasma6.nix
  ../../user/shell/sh.nix
];
```

### Variables from flake.nix

Common attribute sets passed via `extraSpecialArgs`:
- `userSettings` - User settings (username, theme, editor, shell, browser, terminal, wm)
- `systemSettings` - System settings
- `inputs` - Flake inputs
- `pkgs-stable` - Stable package versions

**Related Documentation**: See [user/README.md](../../user/README.md) for directory-level documentation.
