# Komi's macOS Migration Guide

This guide helps you migrate from your current ko-mi/macos-setup to the new Nix-managed dotfiles. You can use Claude Code to help with any step.

## What Changes

| Before (ko-mi/macos-setup) | After (Nix-managed) |
|---------------------------|---------------------|
| Manual Homebrew installs | Declarative in profile config |
| Hammerspoon config in ~/dotfiles | Managed by Home Manager |
| Updates: manual git pull | Updates: `darwin-rebuild switch` |
| Config scattered across files | Centralized in profile config |

## What Stays the Same

- All your Hammerspoon keybindings (Hyper+S for Spotify, etc.)
- Your apps (Arc, Cursor, Obsidian, etc.)
- Touch ID for sudo
- macOS preferences (Dock autohide, etc.)
- Your workflow

## Step-by-Step Migration

### Step 1: Backup Current Setup

```bash
# Backup Hammerspoon config
cp ~/.hammerspoon/init.lua ~/hammerspoon-backup.lua

# Note your currently installed Homebrew packages
brew list > ~/brew-packages-backup.txt
brew list --cask > ~/brew-casks-backup.txt
```

### Step 2: Clone the Dotfiles Repo

```bash
git clone git@github.com:akunito/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

### Step 3: Review Your Profile

Look at your profile config to verify it matches your setup:

```bash
cat profiles/MACBOOK-KOMI-config.nix
```

Key things to check:
- `hostname` - should match or be what you want
- `username` - must be "komi"
- `homebrewCasks` - your GUI apps
- `hammerspoonAppBindings` - your shortcuts
- `gitUser` and `gitEmail` - your git identity

### Step 4: Run the Installation Script

```bash
./install-darwin.sh ~/.dotfiles MACBOOK-KOMI
```

This will:
- Install Nix package manager (if not present)
- Install nix-darwin
- Backup your Homebrew packages
- Apply your MACBOOK-KOMI profile

### Step 5: Verify Everything Works

Test each component:

```bash
# Terminal works
kitty  # Should open with your config

# Starship prompt
# Should see custom prompt in new terminal

# Touch ID for sudo
sudo -v  # Should prompt for fingerprint

# Hammerspoon shortcuts
# Press Hyper+A - Arc should open
# Press Hyper+C - Cursor should open
# Press Hyper+S - Spotify should open
# Press Hyper+M - Window should maximize
```

### Step 6: Clean Up Old Setup (Optional)

```bash
# Remove old ko-mi/macos-setup if you had it elsewhere
rm -rf ~/dotfiles  # or wherever it was

# The old Hammerspoon symlink is replaced by Nix-managed config
```

## Making Changes Going Forward

### Add a New App

Edit `~/.dotfiles/profiles/MACBOOK-KOMI-config.nix`:

```nix
darwin = base.systemSettings.darwin // {
  homebrewCasks = [
    # ... existing apps ...
    "new-app-name"  # Add new app here
  ];
};
```

Then rebuild:
```bash
darwin-rebuild switch --flake ~/.dotfiles#system
```

### Change a Hammerspoon Keybinding

Edit `~/.dotfiles/user/app/hammerspoon/komi-init.lua`:

```lua
-- Change Hyper+S from Spotify to Safari
hs.hotkey.bind(hyperMods, "s", function() launchOrFocus("Safari") end)
```

Then rebuild:
```bash
darwin-rebuild switch --flake ~/.dotfiles#system
```

### Add a New Hammerspoon Shortcut

Edit the `hammerspoonAppBindings` in your profile or add directly to `komi-init.lua`:

```lua
-- Add Hyper+F for Finder
hs.hotkey.bind(hyperMods, "f", function() launchOrFocus("Finder") end)
```

### Update All Packages

```bash
cd ~/.dotfiles
nix flake update
darwin-rebuild switch --flake .#system
```

## Getting Help

You can use Claude Code for any changes:
- "Add Firefox to my Homebrew casks"
- "Change my Hyper+S shortcut to open Safari instead of Spotify"
- "Add a new Hammerspoon binding for Hyper+F to open Finder"
- "Update my dotfiles and rebuild"

## Your Hammerspoon Keybindings Reference

**Hyperkey = Cmd+Ctrl+Alt+Shift (all four modifiers)**

### App Launchers
| Key | App |
|-----|-----|
| S | Spotify |
| T | kitty (Terminal) |
| C | Cursor |
| D | Telegram |
| W | WhatsApp |
| A | Arc |
| O | Obsidian |
| L | Linear |
| G | System Settings |
| P | Passwords |
| Q | Calculator |
| N | Notes |
| X | Calendar |

### Window Cycling
| Key | Action |
|-----|--------|
| 1 | Cycle Arc windows |
| 2 | Cycle Cursor windows |
| 3 | Cycle kitty windows |
| 4 | Cycle Obsidian windows |

### Window Management
| Key | Action |
|-----|--------|
| M | Maximize window |
| H | Minimize (hide) window |
| Left Arrow | Move to left monitor |
| Right Arrow | Move to right monitor |
| J | Left half of screen |
| ; | Right half of screen |
| K | Top half of screen |
| I | Bottom half of screen |
| R | Reload Hammerspoon config |

## Troubleshooting

### Hammerspoon Not Loading

```bash
# Check if Hammerspoon is running
ps aux | grep -i hammerspoon

# Reload config manually
# Click Hammerspoon menu bar icon -> Reload Config

# Check for errors
# Open Console.app, filter by "Hammerspoon"
```

### Touch ID Not Working for Sudo

```bash
# Verify PAM configuration
cat /etc/pam.d/sudo
# Should contain: auth sufficient pam_tid.so

# If missing, rebuild
darwin-rebuild switch --flake ~/.dotfiles#system
```

### Missing App After Rebuild

```bash
# Check if cask exists
brew search --cask <app-name>

# If it exists but not in your config, add it:
# Edit profiles/MACBOOK-KOMI-config.nix
# Add the cask name to homebrewCasks list
# Rebuild
```

### Git Push Failing

```bash
# Ensure SSH key is set up
ssh -T git@github.com

# If needed, generate new key
ssh-keygen -t ed25519 -C "komi@example.com"
# Add to GitHub: Settings -> SSH keys
```

## File Locations

| What | Location |
|------|----------|
| Your profile config | `~/.dotfiles/profiles/MACBOOK-KOMI-config.nix` |
| Hammerspoon config | `~/.dotfiles/user/app/hammerspoon/komi-init.lua` |
| Hammerspoon active config | `~/.hammerspoon/init.lua` (managed by Nix) |
| Homebrew backup | `~/.brew-backup-*.Brewfile` |
