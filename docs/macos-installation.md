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

### 4. Link Profile Flake

```bash
# Choose your profile
ln -sf flake.MACBOOK-KOMI.nix flake.nix
```

### 5. Bootstrap nix-darwin

```bash
nix run nix-darwin -- switch --flake .#system
```

### 6. Rebuild After Changes

```bash
darwin-rebuild switch --flake ~/.dotfiles#system
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
- Arc browser
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

## Updating

```bash
cd ~/.dotfiles
git pull
darwin-rebuild switch --flake .#system
```

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

3. Create the flake entry point:
   ```bash
   cp flake.MACBOOK-KOMI.nix flake.MACBOOK-MYNAME.nix
   # Edit to import your new profile config
   ```

4. Deploy:
   ```bash
   ln -sf flake.MACBOOK-MYNAME.nix flake.nix
   darwin-rebuild switch --flake .#system
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
