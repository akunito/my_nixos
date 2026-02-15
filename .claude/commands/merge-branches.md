# Merge Branches (komi <-> main)

Skill for merging between the main and komi branches safely.

## Pre-merge Audit

1. Detect current branch: `git branch --show-current`
2. Fetch latest: `git fetch origin`
3. Show divergence: `git log --oneline main..origin/komi` and `git log --oneline origin/komi..main`
4. Show diff of shared modules: `git diff <source>...<target> -- user/ lib/ system/`
5. Flag any changes to files the other user shouldn't touch

## Merge Direction

- **main -> komi**: Brings infrastructure improvements to komi
- **komi -> main**: Brings darwin/macOS fixes to main

Ask the user which direction they want, or detect from the current branch.

## Conflict Resolution Rules

| File | Rule |
|------|------|
| flake.nix | Always keep main's unified flake |
| flake.lock | Keep target branch's version |
| CLAUDE.md | Merge both, preserve per-user sections |
| secrets/domains.nix | Always keep main's version |
| secrets/komi/ | Always keep komi's version |
| Shared modules (user/, lib/) | Accept darwin guards, reject global disables |

## Merge Process

1. Create a safety branch: `git checkout -b merge-<source>-into-<target> <target>`
2. Merge: `git merge origin/<source>`
3. Resolve conflicts per rules above
4. For cli-collection.nix: ensure `cava` is in the `!isDarwin` section, not commented out
5. For development.nix: ensure runtimes are behind `developmentFullRuntimesEnable` flag
6. Verify no conflict markers remain: `grep -r '<<<<<<' . --include='*.nix' --include='*.md'`

## Post-merge Verification

Run these evaluations to confirm no breakage:

```bash
# Linux profiles
nix eval .#nixosConfigurations.DESK.config.system.stateVersion
nix eval .#nixosConfigurations.LAPTOP_L15.config.system.stateVersion
nix eval .#nixosConfigurations.LXC_monitoring.config.system.stateVersion

# Darwin profile
nix eval .#darwinConfigurations.MACBOOK-KOMI.config.system.stateVersion
```

## After Merging One Direction

If you merged komi -> main, also sync the other direction:
```bash
git checkout komi
git merge main
```

This ensures both branches are at the same point after the merge.
