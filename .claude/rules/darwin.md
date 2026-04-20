---
paths:
  - "system/darwin/**"
  - "profiles/darwin/**"
  - "profiles/MACBOOK-*"
  - "install-darwin.sh"
---

# Darwin/macOS Rules

## Key References

- **Installation**: `docs/komi/macos-installation.md`
- **Migration**: `docs/komi/macos-komi-migration.md`

## Apply Workflow

```bash
darwin-rebuild switch --flake .#MACBOOK-KOMI
```

## Cross-Platform Module Rules

When modifying shared modules (`user/`, `lib/`, `system/` but not `system/darwin/`):

- Use `pkgs.stdenv.isDarwin` / `lib.mkIf (!pkgs.stdenv.isDarwin)` for platform guards
- Never break existing Linux functionality when adding darwin support
- Never comment out packages globally -- use `lib.optionals` with platform check
- Use feature flags for optional features (default false, each profile enables)

### Examples:

```nix
# Linux-only package
lib.optionals (!pkgs.stdenv.isDarwin) [ pkgs.linux-specific-pkg ]

# Darwin-only configuration
lib.mkIf pkgs.stdenv.isDarwin { ... }

# Feature flag (cross-platform)
lib.mkIf systemSettings.someFeatureEnable { ... }
```

## Homebrew for GUI Apps

Use `systemSettings.darwin.homebrewCasks` for GUI apps (managed by Homebrew), Nix for CLI tools.

## Key Darwin Settings

- `homebrewCasks` -- list of GUI apps installed via Homebrew
- `dockAutohide` -- auto-hide the Dock
- `dockOrientation` -- Dock position (left, bottom, right)
- `touchIdSudo` -- enable Touch ID for sudo
- `keyboardKeyRepeat` -- key repeat rate
