# Darwin Rebuild

Rebuild and apply macOS system configuration using nix-darwin.

## Purpose

Use this skill to:
- Apply changes to macOS system configuration
- Rebuild darwin configuration after modifying Nix files
- Test configuration changes before applying them
- Rollback to previous configurations

---

## Quick Commands

### Apply Changes (Standard)
```bash
cd ~/.dotfiles && sudo darwin-rebuild switch --flake .#system
```

**Alias**: `rebuild`

### Test Build (No Apply)
```bash
cd ~/.dotfiles && darwin-rebuild build --flake .#system
```

**Alias**: `rebuild-test`

---

## When to Use

Use this skill after modifying:
- `profiles/MACBOOK*-config.nix` (system settings)
- `system/darwin/**/*.nix` (system modules)
- `user/**/*.nix` (user configuration via Home Manager)
- `flake.MACBOOK*.nix` (flake configuration)
- Any other Nix configuration files

---

## Common Workflows

### 1. Apply Configuration Changes
```bash
# Standard rebuild (applies changes)
rebuild

# Or manually:
cd ~/.dotfiles && sudo darwin-rebuild switch --flake .#system
```

### 2. Test Before Applying
```bash
# Build configuration without applying (test for errors)
rebuild-test

# If successful, then apply:
rebuild
```

### 3. List Generations
```bash
# List all darwin generations
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# List with details
darwin-rebuild --list-generations
```

### 4. Rollback to Previous Generation
```bash
# Rollback to previous generation
sudo darwin-rebuild --rollback

# Or rollback to specific generation
sudo nix-env --switch-generation <number> -p /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/activate
```

---

## Troubleshooting

### Build Errors

If you encounter build errors:
```bash
# Check for syntax errors in flake
nix flake check

# Try building without switching
rebuild-test

# Check git status (uncommitted changes may cause issues)
cd ~/.dotfiles && git status
```

### Permission Errors

darwin-rebuild requires sudo for system-level changes:
```bash
# Always use sudo for switch/activate
sudo darwin-rebuild switch --flake .#system

# Build-only doesn't need sudo
darwin-rebuild build --flake .#system
```

### Flake Lock Issues

If dependencies are out of sync:
```bash
# Update flake inputs
cd ~/.dotfiles && nix flake update

# Or update specific input
nix flake lock --update-input nixpkgs

# Then rebuild
rebuild
```

---

## What Gets Applied

When you run `darwin-rebuild switch`, it:
1. **Builds** the new system configuration
2. **Activates** system-level changes (Homebrew, system settings, etc.)
3. **Activates** Home Manager user configuration
4. **Creates** a new generation in `/nix/var/nix/profiles/system`

### System-Level Changes
- macOS system preferences (`system/darwin/*.nix`)
- Homebrew packages and casks (`systemSettings.darwin.homebrewCasks`)
- System services (launchd daemons)
- Network configuration
- Security settings (Touch ID, etc.)

### User-Level Changes (Home Manager)
- User applications and packages
- Dotfiles (Hammerspoon, Karabiner, etc.)
- Shell configuration (zsh, bash)
- User services (launchd agents)

---

## Verification After Rebuild

```bash
# Check system generation
darwin-rebuild --list-generations

# Check Home Manager generation
home-manager generations

# Verify specific services
launchctl list | grep <service-name>

# Check Hammerspoon config
ls -l ~/.hammerspoon/init.lua

# Check Karabiner config
ls -l ~/.config/karabiner/karabiner.json
```

---

## Notes

- **sudo is required** for `switch` and `activate` commands
- **Build-only** (`build` or `rebuild-test`) doesn't need sudo
- Changes take effect immediately after `switch`
- Previous configurations can be rolled back using generations
- For Hammerspoon-only changes, you can reload with CL + R instead of full rebuild
