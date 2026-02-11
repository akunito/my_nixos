# Remove App

Remove applications from your Nix/Homebrew configuration and optionally uninstall them from the system.

## Purpose

Use this skill to:
- Remove apps from your declarative configuration
- Optionally uninstall apps from the system
- Clean up unused dependencies
- Keep your config file organized

---

## Usage

Remove an app by name:
```
/remove-app <app-name>
```

**Examples:**
```
/remove-app granola
/remove-app slack
/remove-app ripgrep
```

**With Options:**
```
/remove-app slack --keep-installed    # Remove from config but don't uninstall
/remove-app slack --force             # Skip confirmation prompts
```

---

## How It Works

### 1. Find the App
Searches your profile configuration for the app:
- **macOS**: Checks `darwin.homebrewCasks` and `darwin.homebrewFormulas`
- **Linux**: Checks `systemPackages` and `homePackages`

### 2. Remove from Config
Removes the entry from the appropriate list in your profile config file.

### 3. Apply Changes
Runs the rebuild command to apply the new configuration:
- **macOS**: `darwin-rebuild switch --flake .#system`
- **Linux**: `nixos-rebuild switch --flake .#system`

### 4. Cleanup (Optional)
Optionally uninstalls the app from the system:
- **Homebrew casks**: `brew uninstall --cask <app>`
- **Homebrew formulas**: `brew uninstall <app>`
- **Nix packages**: Removed automatically during rebuild

---

## Removal Flow

### macOS Example
```bash
$ /remove-app slack

Found: slack
Location: profiles/MACBOOK-KOMI-config.nix
Type: Homebrew cask
Category: Communication

Remove slack from configuration? [y/N]: y
Uninstall slack from system? [y/N]: y

Removing slack from configuration...
Running darwin-rebuild switch...
Uninstalling slack...
✓ Successfully removed slack

Homebrew cask slack is no longer installed
```

### Linux Example
```bash
$ /remove-app tmux

Found: tmux
Location: profiles/DESK-config.nix
Type: Nix package (systemPackages)

Remove tmux from configuration? [y/N]: y
Note: tmux will be removed automatically during rebuild

Removing tmux from configuration...
Running nixos-rebuild switch...
✓ Successfully removed tmux

Package tmux is no longer in your PATH
```

---

## Options

### `--keep-installed`
Remove from config but leave installed on system:
```bash
/remove-app slack --keep-installed
```
**Use case**: Testing removal before committing, or keeping app temporarily.

### `--force`
Skip all confirmation prompts:
```bash
/remove-app slack --force
```
**Use case**: Automation or when you're sure about removal.

### `--dry-run`
Preview what would be removed without actually doing it:
```bash
/remove-app slack --dry-run
```
**Output:**
```
Would remove: slack
From: profiles/MACBOOK-KOMI-config.nix
Type: Homebrew cask
Category: Communication
```

---

## Safety Features

### Confirmation Prompts
By default, the skill asks for confirmation:
1. Remove from config? (yes/no)
2. Uninstall from system? (yes/no)

### Backup
Before removal, the current config is backed up:
```bash
# Git status shows changes
cd ~/.dotfiles && git diff profiles/MACBOOK-KOMI-config.nix
```

### Rollback
If something goes wrong, you can rollback:
```bash
# macOS
sudo darwin-rebuild --rollback

# Linux
sudo nixos-rebuild --rollback
```

---

## Common Scenarios

### Remove Unused Apps
Clean up apps you no longer use:
```bash
/remove-app notion
/remove-app linear
/remove-app whatsapp
```

### Remove and Reinstall
Sometimes useful for troubleshooting:
```bash
/remove-app slack
/install-app slack
```

### Keep Config Clean
Remove test apps or duplicates:
```bash
/remove-app vscode        # If you prefer cursor
/remove-app firefox       # If you only use arc
```

---

## Troubleshooting

### App Not Found in Config
```
Error: App "slack" not found in configuration
```
**Solution**: The app might be installed manually or under a different name.
```bash
# Check manually
grep -r "slack" ~/.dotfiles/profiles/

# Or list all apps
/list-apps | grep slack
```

### Can't Uninstall
```
Error: Unable to uninstall slack
```
**Solution**: App might be a dependency or protected.
```bash
# Remove from config only
/remove-app slack --keep-installed

# Check why it can't be uninstalled
brew info slack              # macOS
nix-store --query --referrers /nix/store/*slack*  # Linux
```

### Permission Errors
```
Error: Permission denied
```
**Solution**: Rebuild commands need sudo.
```bash
# macOS
sudo darwin-rebuild switch --flake .#system

# Linux
sudo nixos-rebuild switch --flake .#system
```

---

## Related Skills

- `/install-app` - Install applications
- `/list-apps` - List installed applications
- `/darwin-rebuild` - Apply macOS configuration

---

## Notes

- **Declarative config**: Apps are managed in config files, not imperatively
- **Nix packages**: Automatically garbage collected after removal
- **Homebrew casks**: Require explicit uninstall command
- **Dependencies**: Only explicitly listed apps are removed (dependencies may remain)
- **Git tracked**: All config changes are tracked in git
- **Reversible**: Can always rollback or re-add apps

---

## Implementation Details

The skill workflow:

1. **Parse arguments**: Extract app name and options
2. **Find app**: Search profile config for the app entry
3. **Confirm removal**: Prompt user for confirmation (unless --force)
4. **Update config**: Remove app from the appropriate list
5. **Apply changes**: Run darwin-rebuild or nixos-rebuild
6. **Uninstall**: Optionally run brew uninstall (unless --keep-installed)
7. **Verify**: Check that app is no longer accessible
8. **Report**: Show removal status

---

## Examples

### Remove with Confirmation (Default)
```bash
$ /remove-app granola

Found: granola
Location: profiles/MACBOOK-KOMI-config.nix
Type: Homebrew cask
Category: Productivity

Remove granola from configuration? [y/N]: y
Uninstall granola from system? [y/N]: y

Removing granola from configuration...
Running darwin-rebuild switch...
Uninstalling granola...
✓ Successfully removed granola

Application granola is no longer installed
```

### Remove Without Uninstall
```bash
$ /remove-app granola --keep-installed

Found: granola
Location: profiles/MACBOOK-KOMI-config.nix
Type: Homebrew cask

Removing granola from configuration (keeping installed)...
Running darwin-rebuild switch...
✓ Configuration updated (app still installed)

Note: granola is still installed but no longer in config
Run 'brew uninstall --cask granola' to fully remove
```

### Force Remove
```bash
$ /remove-app granola --force

Removing granola from configuration...
Running darwin-rebuild switch...
Uninstalling granola...
✓ Successfully removed granola
```

---

## Safety & Best Practices

- **Review changes**: Always check git diff before committing
- **Test in dry-run**: Use `--dry-run` for unfamiliar apps
- **Keep dependencies**: Don't remove system dependencies
- **Backup first**: Ensure git is up to date
- **Rollback available**: Can always undo with rollback command
- **Commit changes**: Configuration changes are tracked in git

---

## Advanced Usage

### Remove Multiple Apps
```bash
# Remove apps one by one
/remove-app slack
/remove-app notion
/remove-app spotify
```

### Batch Remove (Future Enhancement)
```bash
# Remove multiple apps at once
/remove-app slack notion spotify --force
```

### Clean Unused Dependencies
```bash
# macOS
brew cleanup
brew autoremove

# Linux
nix-collect-garbage -d
```
