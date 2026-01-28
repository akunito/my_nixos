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

## When Unsure

Use `docs/00_ROUTER.md` to pick the right doc node, then read only the relevant docs/code.
