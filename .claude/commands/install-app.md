# Install App

Intelligently install applications using Nix package manager or Homebrew based on the platform and app availability.

## Purpose

Use this skill to:
- Install GUI apps via Homebrew casks (macOS)
- Install CLI tools via Nix packages (cross-platform)
- Automatically detect the appropriate profile config
- Place apps in the correct category
- Apply changes automatically

---

## Usage

Simply invoke with the app name:
```
/install-app <app-name>
```

**Examples:**
```
/install-app granola
/install-app slack
/install-app ripgrep
/install-app vscode
```

---

## How It Works

### 1. Platform Detection
The skill automatically detects:
- **macOS (darwin)**: Prefers Homebrew casks for GUI apps, Nix for CLI tools
- **Linux (NixOS)**: Uses Nix packages exclusively

### 2. Package Discovery
Searches for the app in:
1. **Homebrew casks** (macOS GUI apps): `brew search --cask <app>`
2. **Nix packages** (CLI tools): `nix search nixpkgs <app>`
3. **Homebrew formulas** (CLI tools): `brew search <app>`

### 3. Profile Configuration
Automatically finds and updates the correct profile:
- **macOS**: `profiles/MACBOOK-<hostname>-config.nix`
- **Linux**: `profiles/<HOSTNAME>-config.nix` or `profiles/LXC_<hostname>-config.nix`

### 4. Intelligent Categorization
Places apps in the appropriate section:

**macOS (Homebrew Casks):**
- `# === Browsers ===` (arc, firefox, chrome, etc.)
- `# === Development ===` (cursor, vscode, etc.)
- `# === Communication ===` (slack, discord, telegram, etc.)
- `# === Productivity ===` (notion, obsidian, linear, etc.)
- `# === Media ===` (spotify, vlc, etc.)
- `# === Utilities ===` (raycast, alfred, etc.)

**Linux (Nix Packages):**
- `systemPackages` (system-level tools)
- `homePackages` (user-level applications)

### 5. Apply Changes
Automatically runs the appropriate rebuild command:
- **macOS**: `darwin-rebuild switch --flake .#system`
- **Linux**: `nixos-rebuild switch --flake .#system`

---

## Installation Flow

### macOS Example
```bash
# User runs: /install-app slack

# 1. Search Homebrew casks
brew search --cask slack
# Found: slack

# 2. Determine category
# "slack" → Communication

# 3. Update profile config
# Edit: profiles/MACBOOK-KOMI-config.nix
# Add to: darwin.homebrewCasks under "# === Communication ==="

# 4. Apply changes
darwin-rebuild switch --flake .#system

# 5. Verify installation
ls /Applications/ | grep -i slack
```

### Linux Example
```bash
# User runs: /install-app tmux

# 1. Search nixpkgs
nix search nixpkgs tmux
# Found: pkgs.tmux

# 2. Determine package type
# CLI tool → systemPackages (if system-level) or homePackages (if user-level)

# 3. Update profile config
# Edit: profiles/DESK-config.nix
# Add to: systemSettings.systemPackages or userSettings.homePackages

# 4. Apply changes
sudo nixos-rebuild switch --flake .#system

# 5. Verify installation
which tmux
```

---

## Categories Reference

### Homebrew Cask Categories (macOS)
| Category | Examples |
|----------|----------|
| Browsers | arc, firefox, chrome, brave |
| Development | cursor, vscode, xcode, docker |
| Communication | slack, discord, telegram, whatsapp, zoom |
| Productivity | notion, obsidian, linear, granola, evernote |
| Media | spotify, vlc, iina, transmission |
| Utilities | raycast, alfred, rectangle, karabiner-elements |

### Nix Package Types (Linux/macOS)
| Type | Location | Purpose |
|------|----------|---------|
| System | `systemSettings.systemPackages` | System-wide CLI tools |
| User | `userSettings.homePackages` | User-specific applications |
| Module Flags | `systemSettings.*Enable` | Feature flags for package modules |

---

## Profile File Locations

### macOS
```
~/.dotfiles/profiles/
├── MACBOOK-base.nix           # Shared macOS settings
├── MACBOOK-KOMI-config.nix    # Komi's profile
└── flake.MACBOOK_KOMI.nix     # Flake entry point
```

### Linux Personal
```
~/.dotfiles/profiles/
├── DESK-config.nix            # Desktop workstation
├── LAPTOP-base.nix            # Laptop base config
├── LAPTOP_L15-config.nix      # ThinkPad L15
└── AGA-config.nix             # Aga's machine
```

### Linux LXC Containers
```
~/.dotfiles/profiles/
├── LXC-base-config.nix        # Base LXC config
├── LXC_HOME-config.nix        # Homelab services
├── LXC_plane-config.nix       # Plane project management
└── LXC_monitoring-config.nix  # Grafana/Prometheus
```

---

## Troubleshooting

### App Not Found
If the app isn't found in search:
```bash
# Try alternate names
/install-app visual-studio-code  # Instead of "vscode"
/install-app google-chrome        # Instead of "chrome"

# Search manually first
brew search <app>
nix search nixpkgs <app>
```

### Wrong Category
The skill makes a best guess based on app name/type. If miscategorized:
1. Let it install
2. Manually move to correct category in config file
3. Mention the issue so I can learn better categorization

### Permission Errors
```bash
# macOS: darwin-rebuild needs sudo
sudo darwin-rebuild switch --flake .#system

# Linux: nixos-rebuild needs sudo
sudo nixos-rebuild switch --flake .#system
```

### Homebrew vs Nix Decision
**Prefer Homebrew casks for:**
- GUI applications (visual interfaces)
- Apps from Mac App Store equivalents
- Apps without good Nix packages

**Prefer Nix packages for:**
- CLI tools and utilities
- Development tools
- Cross-platform consistency

---

## Advanced Usage

### Install Multiple Apps
```bash
# Install apps one by one
/install-app slack
/install-app notion
/install-app spotify
```

### Force Package Type
If you want to override the automatic detection:
```bash
# Force Homebrew formula (CLI tool)
/install-app docker --formula

# Force Homebrew cask (GUI app)
/install-app docker --cask

# Force Nix package
/install-app docker --nix
```

### Dry Run (Preview Only)
```bash
# See what would be installed without applying
/install-app slack --dry-run
```

---

## Related Skills

- `/darwin-rebuild` - Apply macOS configuration changes
- `/setup-project-docs` - Initialize project documentation
- `/audit-project-security` - Security audit for projects

---

## Notes

- **GUI apps on macOS**: Always use Homebrew casks (not Nix)
- **CLI tools**: Prefer Nix for consistency across machines
- **Automatic categorization**: Best effort based on app name/type
- **Config changes**: All changes are committed to git
- **Declarative**: Once installed via this skill, the app persists across rebuilds
- **Idempotent**: Running twice won't duplicate entries

---

## Implementation Details

The skill follows this workflow:

1. **Parse arguments**: Extract app name and optional flags
2. **Detect platform**: Check `uname` or `systemSettings.osType`
3. **Search registries**: Try Homebrew casks, Nix packages, Homebrew formulas
4. **Find profile**: Match hostname to profile config file
5. **Determine category**: Use heuristics based on app name/type
6. **Update config**: Add to appropriate list in profile config
7. **Apply changes**: Run darwin-rebuild or nixos-rebuild
8. **Verify**: Check if app is accessible/installed
9. **Report**: Show installation status and location

---

## Examples

### Install Slack (macOS)
```bash
$ /install-app slack

Searching for 'slack'...
✓ Found: slack (Homebrew cask)

Profile: profiles/MACBOOK-KOMI-config.nix
Category: Communication
Location: darwin.homebrewCasks

Adding slack to configuration...
Running darwin-rebuild switch...
✓ Successfully installed slack

Verify: open -a Slack
```

### Install ripgrep (Linux)
```bash
$ /install-app ripgrep

Searching for 'ripgrep'...
✓ Found: pkgs.ripgrep (Nix package)

Profile: profiles/DESK-config.nix
Type: System package (CLI tool)
Location: systemSettings.systemPackages

Adding ripgrep to configuration...
Running nixos-rebuild switch...
✓ Successfully installed ripgrep

Verify: which rg
```

---

## Safety & Best Practices

- **Review changes**: Always check git diff before committing
- **Test in dry-run**: Use `--dry-run` for unfamiliar apps
- **Read descriptions**: The skill shows package descriptions before installing
- **Rollback available**: Use `darwin-rebuild --rollback` or `nixos-rebuild --rollback` if needed
- **Commit changes**: Configuration changes are tracked in git

---

## Future Enhancements

Potential improvements:
- Interactive category selection
- Bulk installation from list
- Remove app command (`/remove-app`)
- Update/upgrade specific apps
- Show installed apps (`/list-apps`)
- Search without installing (`/search-app`)
