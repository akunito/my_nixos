# List Apps

List all applications managed by your Nix/Homebrew configuration.

## Purpose

Use this skill to:
- View all apps in your declarative configuration
- See apps organized by category or type
- Find where apps are defined
- Audit your installed applications
- Quickly check if an app is managed

---

## Usage

List all apps:
```
/list-apps
```

**With Filters:**
```
/list-apps --category productivity  # Filter by category
/list-apps --type cask              # Filter by type
/list-apps --search slack           # Search for specific app
/list-apps --profile MACBOOK-KOMI   # List apps from specific profile
```

---

## Output Formats

### Default (Organized by Category)
```
=== macOS Apps (Homebrew) ===

Browsers:
  • arc
  • firefox

Development:
  • cursor
  • hammerspoon

Communication:
  • telegram
  • whatsapp
  • discord
  • slack

Productivity:
  • obsidian
  • linear-linear
  • notion
  • granola

Media:
  • spotify

Utilities:
  • kitty
  • raycast
  • 1password
  • karabiner-elements

=== CLI Tools (Homebrew Formulas) ===
  • docker
  • docker-compose
  • colima

Total: 21 apps
```

### Flat List (`--flat`)
```
arc
cursor
discord
docker
docker-compose
colima
granola
hammerspoon
karabiner-elements
kitty
linear-linear
notion
obsidian
raycast
slack
spotify
telegram
1password
whatsapp
```

### Detailed (`--detailed`)
```
App: arc
Type: Homebrew cask
Category: Browsers
Profile: profiles/MACBOOK-KOMI-config.nix
Line: 16

App: cursor
Type: Homebrew cask
Category: Development
Profile: profiles/MACBOOK-KOMI-config.nix
Line: 19

...
```

---

## Filters

### By Category
```bash
/list-apps --category productivity

=== Productivity Apps ===
  • obsidian
  • linear-linear
  • notion
  • granola

Total: 4 apps
```

### By Type
```bash
/list-apps --type cask

=== Homebrew Casks ===
  • arc
  • cursor
  • telegram
  ...

Total: 18 apps
```

Available types:
- `cask` - Homebrew casks (GUI apps, macOS only)
- `formula` - Homebrew formulas (CLI tools, macOS only)
- `nix-system` - Nix system packages
- `nix-user` - Nix user packages

### By Search
```bash
/list-apps --search discord

Found 1 match:

App: discord
Type: Homebrew cask
Category: Communication
Profile: profiles/MACBOOK-KOMI-config.nix
```

### By Profile
```bash
/list-apps --profile DESK

Profile: profiles/DESK-config.nix

=== System Packages ===
  • vim
  • git
  • tmux
  ...

=== User Packages ===
  • firefox
  • vscode
  ...

Total: 45 apps
```

---

## Categories

### macOS (Homebrew)
- **Browsers**: Web browsers
- **Development**: IDEs, dev tools, terminal apps
- **Communication**: Chat, video call, email apps
- **Productivity**: Note-taking, project management, AI tools
- **Media**: Music, video, streaming apps
- **Utilities**: System utilities, launchers, window managers

### Linux (Nix)
- **System Packages**: System-wide CLI tools
- **User Packages**: User-specific applications
- **Module Flags**: Feature flags that enable package modules

---

## Use Cases

### Audit Installed Apps
Check what's currently in your config:
```bash
/list-apps
```

### Find an App
Check if an app is already installed:
```bash
/list-apps --search vscode
```

### Review Category
See all apps in a specific category:
```bash
/list-apps --category communication
```

### Compare Profiles
List apps from different machines:
```bash
/list-apps --profile MACBOOK-KOMI
/list-apps --profile DESK
```

### Export List
Get a flat list for documentation:
```bash
/list-apps --flat > my-apps.txt
```

---

## Platform-Specific Behavior

### macOS
Shows:
- Homebrew casks (GUI apps)
- Homebrew formulas (CLI tools)
- Nix packages (if any)

Sources:
- `darwin.homebrewCasks`
- `darwin.homebrewFormulas`
- `systemSettings.systemPackages`
- `userSettings.homePackages`

### Linux (NixOS)
Shows:
- System packages
- User packages (Home Manager)
- Feature flags (enabled modules)

Sources:
- `systemSettings.systemPackages`
- `userSettings.homePackages`
- `*Enable` flags

---

## Output Options

### `--flat`
Simple list, one app per line (good for scripting):
```bash
/list-apps --flat
```

### `--detailed`
Full details for each app:
```bash
/list-apps --detailed
```

### `--json`
JSON format (for programmatic use):
```bash
/list-apps --json

{
  "casks": ["arc", "cursor", ...],
  "formulas": ["docker", "colima"],
  "categories": {
    "browsers": ["arc"],
    "development": ["cursor", "hammerspoon"],
    ...
  },
  "total": 21
}
```

### `--count`
Show counts only:
```bash
/list-apps --count

Homebrew Casks: 18
Homebrew Formulas: 3
Total: 21
```

---

## Comparison with System

### Check Config vs Installed
See what's in config vs actually installed:
```bash
/list-apps --compare

=== In Config but Not Installed ===
  • granola (install with: brew install --cask granola)

=== Installed but Not in Config ===
  • figma (managed outside Nix/Homebrew)
  • zoom.us (add with: /install-app zoom)

=== In Sync ===
  • arc ✓
  • cursor ✓
  • slack ✓
  ...
```

---

## Examples

### Basic List
```bash
$ /list-apps

=== macOS Apps (Homebrew) ===

Browsers:
  • arc

Development:
  • cursor
  • hammerspoon

Communication:
  • telegram
  • whatsapp
  • discord

Productivity:
  • obsidian
  • linear-linear
  • notion
  • granola

Media:
  • spotify

Utilities:
  • kitty
  • raycast
  • 1password
  • karabiner-elements

Total: 18 casks, 3 formulas = 21 apps
```

### Search for App
```bash
$ /list-apps --search slack

Found 1 match:

App: slack
Type: Homebrew cask
Category: Communication
Profile: profiles/MACBOOK-KOMI-config.nix
Line: 25
Installed: Yes
```

### List by Category
```bash
$ /list-apps --category development

=== Development Apps ===
  • cursor
  • hammerspoon
  • docker
  • docker-compose
  • colima

Total: 5 apps
```

### Flat List
```bash
$ /list-apps --flat

arc
cursor
discord
docker
docker-compose
colima
granola
hammerspoon
karabiner-elements
kitty
linear-linear
notion
obsidian
raycast
slack
spotify
telegram
1password
whatsapp
```

---

## Troubleshooting

### No Apps Listed
```
No apps found in configuration
```
**Solution**: Check if you're in the correct profile or if config is loaded.
```bash
# Verify profile file exists
ls -l ~/.dotfiles/profiles/MACBOOK-KOMI-config.nix

# Check git status
cd ~/.dotfiles && git status
```

### App Installed but Not Listed
If an app is installed but not showing:
- App might be installed manually (not in Nix/Homebrew config)
- App might be in a different profile
- App might be a dependency (not explicitly listed)

```bash
# Check if it's installed via Homebrew
brew list | grep <app>

# Check if it's in PATH (Nix)
which <app>
```

---

## Related Skills

- `/install-app` - Install applications
- `/remove-app` - Remove applications
- `/darwin-rebuild` - Apply macOS configuration

---

## Notes

- **Declarative config**: Only shows apps explicitly listed in config
- **Dependencies**: Doesn't show automatic dependencies
- **Manual installs**: Apps installed outside Nix/Homebrew won't appear
- **Multi-profile**: Shows apps from the current profile only (unless --profile)
- **Cached**: Reads from config files, not from system state

---

## Implementation Details

The skill workflow:

1. **Detect platform**: macOS or Linux
2. **Find profile**: Determine current profile config file
3. **Parse config**: Extract app lists from profile
4. **Categorize**: Group apps by category and type
5. **Filter**: Apply any filters (category, type, search)
6. **Format**: Output in requested format (default, flat, detailed, json)
7. **Count**: Calculate totals per type and category
8. **Report**: Display organized list

---

## Advanced Usage

### Diff Between Profiles
```bash
# List apps from two profiles
/list-apps --profile MACBOOK-KOMI --flat > komi.txt
/list-apps --profile DESK --flat > desk.txt
diff komi.txt desk.txt
```

### Check for Duplicates
```bash
# List all apps and check for duplicates
/list-apps --flat | sort | uniq -d
```

### Generate Documentation
```bash
# Create a markdown list of apps
/list-apps --detailed > APPS.md
```

### Audit App Count
```bash
# Track app count over time
/list-apps --count

# Compare with previous count
echo "$(date): $(/list-apps --count)" >> app-count-history.txt
```

---

## Safety & Best Practices

- **Regular audits**: Run periodically to review your app list
- **Clean unused**: Use `/remove-app` for apps you don't use
- **Document**: Keep app list in project documentation
- **Compare profiles**: Sync apps across machines if needed
- **Version control**: Config changes tracked in git

---

## Future Enhancements

Potential improvements:
- Interactive app management (select to remove)
- Dependency tree visualization
- Installation date tracking
- Usage statistics integration
- Recommendations based on usage
- Export to various formats (CSV, YAML, etc.)
