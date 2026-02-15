---
id: workflow.komi-onboarding
summary: Quick guide for ko-mi on the multi-user branch setup and what changed
tags: [komi, onboarding, multi-user, darwin]
date: 2026-02-15
status: published
---

# Hey Komi! Here's what changed

We merged your `komi` branch into `main` and set up a proper multi-user workflow so we can both work on the same repo without stepping on each other's toes.

## TL;DR

- Your branch (`komi`) and mine (`main`) are now fully synced
- You keep working on `komi`, I keep working on `main`, we merge regularly
- Your darwin/macOS stuff is safe and won't break my Linux configs (and vice versa)
- We each get our own encrypted secrets directory

## What got merged

All 18 of your commits are now on `main`:
- Hammerspoon + Karabiner-Elements setup
- Homebrew cask management (Arc, Cursor, Spotify, etc.)
- Stylix theming with Ashes palette
- Darwin system defaults, security (Touch ID), homebrew formulas
- Terminal fixes (alacritty, kitty, tmux null-checks)
- Claude Code skills (audit-project-docs, install-app, etc.)
- Colima/Docker setup

And all ~250 of my infrastructure commits are now on your `komi` branch too.

## Two things we fixed in your code

### 1. `cava` package

You commented out `cava` globally because it doesn't build on macOS. Instead of commenting it out (which removes it from Linux too), we moved it to the Linux-only section:

```nix
# Before (your fix — breaks Linux):
# cava  # Disabled: build fails on macOS

# After (proper fix — works on both):
++ lib.optionals (!pkgs.stdenv.isDarwin) [
  cava  # Audio visualizer (Linux only)
  ...
]
```

**Rule of thumb**: Never comment out packages globally. Use `lib.optionals (!pkgs.stdenv.isDarwin)` for Linux-only, or `lib.optionals pkgs.stdenv.isDarwin` for macOS-only.

### 2. Development runtimes (Node.js, Python, Go, Rust)

You added these directly to `development.nix`. That's fine for you, but I don't need them on all my profiles. So we put them behind a flag:

```nix
# In lib/defaults.nix (default off):
developmentFullRuntimesEnable = false;

# In your MACBOOK-KOMI-config.nix (enabled for you):
developmentFullRuntimesEnable = true;
```

Now you keep your runtimes, and my profiles don't get them unless I explicitly enable the flag.

## Your secrets directory

We set up `secrets/komi/` for your personal encrypted secrets. Right now there's just a template. When you need encrypted secrets:

```bash
# One-time setup (run on your machine):
git-crypt init --key-name komi
git-crypt export-key --key-name komi ~/komi-git-crypt-key

# Then copy secrets/komi/secrets.nix.template to secrets/komi/secrets.nix
# and fill in your real values
```

My `secrets/domains.nix` stays encrypted with my key — you can't read it, and I can't read yours.

## How we work going forward

### Your branch rules

**Go wild with:**
- `profiles/MACBOOK-KOMI-config.nix` — your profile
- `profiles/darwin/`, `system/darwin/` — darwin-specific stuff
- `user/app/hammerspoon/komi-init.lua` — your Hammerspoon config
- `secrets/komi/` — your secrets
- `.claude/commands/` — Claude Code skills

**Be careful with shared modules** (`user/`, `lib/`, `system/`):
- You CAN add darwin guards (`lib.mkIf isDarwin`, `lib.optionals !isDarwin`)
- You CAN add defensive null-checks (those help everyone)
- DON'T remove Linux functionality or comment things out globally
- For new features, add a flag to `lib/defaults.nix` (default `false`), enable it in your profile

**Don't touch:**
- `secrets/domains.nix` — my encrypted secrets
- `flake.nix` — the unified flake (managed on main)
- LXC profiles, system services

### Merging

We merge regularly to keep both branches up to date. There's a `/merge-branches` Claude Code skill that automates this.

Typical flow:
1. I merge `komi -> main` when you have stable changes
2. Then merge `main -> komi` so you get my latest infrastructure updates
3. Both branches stay in sync

### Rebuilding your system

Same as before:
```bash
darwin-rebuild switch --flake .#MACBOOK-KOMI
```

## Files reference

| File | What it does |
|------|-------------|
| `docs/multi-user-workflow.md` | Full merge workflow, rules, and checklists |
| `.claude/commands/merge-branches.md` | `/merge-branches` skill for Claude Code |
| `secrets/komi/secrets.nix.template` | Template for your encrypted secrets |
| `.gitattributes` | git-crypt-komi filter for your secrets |

That's it! Keep doing what you're doing on the `komi` branch and we'll merge periodically.
