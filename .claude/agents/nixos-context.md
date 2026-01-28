# NixOS Agent Context

This context applies when working with NixOS/flake files: `**/*.nix`, `flake.nix`, `flake.*.nix`, `flake.lock`

## Invariants (always follow)

- **Immutability**: never suggest editing `/nix/store` or running imperative package managers (`nix-env`, `nix-channel`, `apt`, `yum`).
- **Source of truth**: `flake.nix` + `inputs` control dependencies; use Nix options/modules, not ad-hoc system changes.
- **Apply workflow**: apply changes via `install.sh` (or `phoenix sync`), not manual `systemctl enable`/`systemctl start`.
- **Flake purity**: prefer repo-relative paths (`./.`) and `self`; avoid absolute host paths in Nix expressions.

## System vs User Boundaries

- system-wide packages: `environment.systemPackages`
- per-user packages: `home.packages`
- system services: `services.*`
- user services/programs: `systemd.user.*` / `programs.*` (Home Manager)

## Home Manager Updates

When modifying Home Manager configuration (user-level modules), apply changes using:

```bash
cd /home/akunito/.dotfiles && ./sync-user.sh
```

## LXC Container Pattern

For Proxmox LXC containers, use the **Base + Override** pattern:
- Common settings in `profiles/LXC-base-config.nix`
- Hostname/specific overrides in `profiles/<NAME>-config.nix`
- Point `flake.<NAME>.nix` to the override

## Modular Configuration (CRITICAL)

**NEVER** hardcode hostname or profile checks in modules. Use feature flags instead:

### ❌ BAD (hardcoded):
```nix
lib.mkIf (systemSettings.hostname == "nixosaku") { ... }
lib.mkIf (systemSettings.profile == "personal") { ... }
```

### ✅ GOOD (feature flags):
```nix
lib.mkIf systemSettings.sddmBreezePatchedTheme { ... }
lib.mkIf systemSettings.atuinAutoSync { ... }
```

### Rules:
1. **All conditional features must use flags** defined in `lib/defaults.nix`
2. **Flags default to `false`** (or safe value) - profiles explicitly enable what they need
3. **GPU-specific code** must check `systemSettings.gpuType` (values: "amd", "intel", "nvidia", "none")
4. **Profile configs set flags** - modules just consume them
5. **Profile checks are OK** for broad categories (e.g., `profile == "homelab"` for server tuning)

### Examples of correct flags:
- `gpuType` - GPU driver selection ("amd", "intel", "nvidia", "none")
- `enableDesktopPerformance` / `enableLaptopPerformance` - Performance tuning
- `sddmForcePasswordFocus` / `sddmBreezePatchedTheme` - SDDM customization
- `atuinAutoSync` - Shell history cloud sync
- `amdLACTdriverEnable` - AMD GPU control application

## When Unsure

Use `docs/00_ROUTER.md` to pick the right doc node, then read only the relevant docs/code.
