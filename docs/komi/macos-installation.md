# macOS Installation Guide

This guide covers installing and configuring this dotfiles repository on macOS using nix-darwin and Home Manager.

## Prerequisites

- macOS 12 (Monterey) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- Admin access to install software
- Git installed (comes with Xcode Command Line Tools)

### Install Xcode Command Line Tools

```bash
xcode-select --install
```

## Quick Start

For a fresh Mac, run the automated installer:

```bash
# Clone the repository
git clone https://github.com/akunito/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Run the darwin installer with your profile
./install-darwin.sh ~/.dotfiles MACBOOK-KOMI
```

This will:
1. Install Nix package manager
2. Install Homebrew (for GUI apps)
3. Bootstrap nix-darwin
4. Apply your profile configuration

## Available Profiles

| Profile | Description |
|---------|-------------|
| `MACBOOK-KOMI` | Komi's MacBook setup (Arc, Cursor, Obsidian, Hammerspoon) |
| `MACBOOK` | Base MacBook profile (customize for your needs) |

## Manual Installation

If you prefer to install step-by-step:

### 1. Install Nix

```bash
# Using Determinate Systems installer (recommended)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Restart your terminal or source nix
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### 2. Install Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add to PATH (Apple Silicon)
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 3. Clone Dotfiles

```bash
git clone https://github.com/akunito/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

### 4. Set Active Profile

```bash
echo "MACBOOK-KOMI" > .active-profile
```

### 5. Bootstrap nix-darwin

```bash
nix run nix-darwin -- switch --flake .#MACBOOK-KOMI
```

### 6. Rebuild After Changes

```bash
darwin-rebuild switch --flake ~/.dotfiles#MACBOOK-KOMI
```

## What Gets Installed

### Terminal & Shell Setup (Matching DESK Profile)

The darwin profile uses the **same terminal modules** as the DESK (Linux) profile:

| Module | Description | Cross-Platform |
|--------|-------------|----------------|
| `sh.nix` | zsh/bash config, direnv, atuin, starship | Yes |
| `tmux.nix` | tmux with session persistence | Yes (pbcopy on macOS) |
| `kitty.nix` | kitty terminal with tmux auto-start | Yes |
| `alacritty.nix` | alacritty terminal with tmux auto-start | Yes |
| `cli-collection.nix` | fd, bat, eza, ripgrep, fzf, jq, etc. | Yes (Linux-only tools excluded) |
| `ranger.nix` | ranger file manager | Yes (pbcopy on macOS) |
| `git.nix` | git configuration | Yes |
| `nixvim.nix` | NixVim (Cursor-like IDE) | Yes (conditional) |
| `aichat.nix` | AI chat CLI tool | Yes (conditional) |

### Via Nix (CLI tools)
- zsh, starship, tmux
- git, neovim (nixvim)
- fd, bat, eza, ripgrep, fzf, jq
- ranger file manager
- Development tools

### Via Homebrew Casks (GUI apps)
Configured per-profile in `profiles/MACBOOK-*-config.nix`:
- Zen browser
- Cursor IDE
- Obsidian
- Hammerspoon
- And more...

### System Configuration
- Touch ID for sudo
- Dock preferences (autohide, position)
- Finder preferences (show extensions, hidden files)
- Keyboard settings (fast key repeat)
- Trackpad settings (tap to click)

## Hammerspoon Keybindings

The MACBOOK-KOMI profile includes Hammerspoon for window management.

**Hyperkey = Cmd+Ctrl+Alt+Shift**

| Key | Action |
|-----|--------|
| Hyper+S | Spotify |
| Hyper+T | Terminal (kitty) |
| Hyper+C | Cursor |
| Hyper+A | Arc |
| Hyper+O | Obsidian |
| Hyper+M | Maximize window |
| Hyper+H | Minimize window |
| Hyper+Left | Move window to left monitor |
| Hyper+Right | Move window to right monitor |
| Hyper+R | Reload Hammerspoon config |

See `user/app/hammerspoon/komi-init.lua` for all bindings.

## Troubleshooting

### "darwin-rebuild: command not found"

Restart your terminal or run:
```bash
. /etc/static/bashrc  # or /etc/static/zshrc
```

### Homebrew casks not installing

Ensure Homebrew is in PATH:
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### Touch ID not working for sudo

Verify PAM configuration:
```bash
cat /etc/pam.d/sudo
# Should contain: auth sufficient pam_tid.so
```

### Hammerspoon not loading config

1. Check if Hammerspoon is running (menu bar icon)
2. Click menu bar icon -> Reload Config
3. Check Console.app for Hammerspoon errors

## Managing installed apps

**The declared list is the only source of truth.** Apps are never installed ad hoc.

| Want to... | Do this |
|------------|---------|
| Add a GUI app | Add the cask to `systemSettings.darwin.homebrewCasks` in `profiles/MACBOOK-KOMI-config.nix`, then rebuild |
| Add a CLI tool | Add the package to `homePackages` in the same profile, then rebuild |
| Remove an app | Delete its entry from the profile, then rebuild |

Do **not** run `brew install`, `brew install --cask`, `brew uninstall`, or
`nix-env -i`. `homebrewOnActivation.cleanup = "zap"` (set in `lib/defaults.nix`)
uninstalls and zaps every cask that is not listed in `homebrewCasks` on the next
rebuild, so anything installed ad hoc is deleted — along with its data — the
next time anyone rebuilds.

These commands are blocked by Claude Code deny rules in
`user/app/claude-code/claude-code.nix`. Read-only brew commands (`brew list`,
`brew info`, `brew search`, `brew outdated`) remain available.

## Updating

```bash
cd ~/.dotfiles
git pull
./scripts/darwin-rebuild.sh MACBOOK-KOMI
```

### Always rebuild through the wrapper

`./scripts/darwin-rebuild.sh [PROFILE]` replaces calling `darwin-rebuild switch`
directly.

nix-darwin runs Homebrew early in the activation script, **before** home-manager.
Any non-zero exit there aborts the switch partway: `/etc`, launchd, pam and fonts
are applied, but the system profile is never switched and no user config is
linked — while the terminal output still looks like a success, because the
failure is buried under hundreds of lines of Homebrew output.

The wrapper records the store path the build should produce, runs the switch,
then asserts `/run/current-system` actually advanced to it. A half-applied system
fails loudly instead of silently. It also detects the specific case where
`brew bundle` degrades into a dry run, which is what caused this failure mode
historically.

## Creating Your Own Profile

1. Copy an existing profile:
   ```bash
   cp profiles/MACBOOK-KOMI-config.nix profiles/MACBOOK-MYNAME-config.nix
   ```

2. Edit the profile to customize:
   - `hostname`
   - `username`
   - `homebrewCasks` (your GUI apps)
   - `hammerspoonAppBindings` (your shortcuts)

3. Register in unified `flake.nix`:
   ```nix
   # Add to the profiles map in flake.nix:
   MACBOOK-MYNAME = ./profiles/MACBOOK-MYNAME-config.nix;
   ```

4. Deploy:
   ```bash
   echo "MACBOOK-MYNAME" > .active-profile
   darwin-rebuild switch --flake .#MACBOOK-MYNAME
   ```

## Architecture

```
profiles/
├── darwin/
│   ├── configuration.nix  # Base nix-darwin config
│   └── home.nix           # Base Home Manager config
├── MACBOOK-base.nix       # Shared MacBook settings
└── MACBOOK-KOMI-config.nix # Komi's specific config

system/darwin/
├── defaults.nix    # macOS system preferences
├── homebrew.nix    # Homebrew management
├── keyboard.nix    # Keyboard settings
└── security.nix    # Touch ID, firewall

user/app/hammerspoon/
├── hammerspoon.nix # Home Manager module
└── komi-init.lua   # Komi's Hammerspoon config
```
