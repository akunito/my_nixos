# Phoenix to Aku Command Rename Plan

## Overview

This document outlines the plan to replace all "phoenix" command references with "aku" throughout the dotfiles repository. The rename affects 33 files with 128 total occurrences.

## Impact Analysis

### Files Affected by Category

#### 1. Binary/Command Files (1 file)
- `system/bin/phoenix.nix` → **RENAME TO** → `system/bin/aku.nix`

#### 2. Documentation Files (11 files)
- `.claude/AGENTS.md`
- `CLAUDE.md`
- `README.md`
- `docs/00_ROUTER.md`
- `docs/01_CATALOG.md`
- `docs/future/migrate-agents.md`
- `docs/nix-modules/dotfiles-management.md`
- `docs/nix-modules/home-manager.md`
- `docs/system-modules/system-applications.md`
- `docs/user-modules/shell.md`
- `docs/user-modules/tmux.md`

#### 3. Agent Context Files (12 files)
- `.agent/nix-module-specialist.md`
- `.agent/nix-profile-specialist.md`
- `.claude/agents/nix-module-specialist.md`
- `.claude/agents/nix-profile-specialist.md`
- `.cursor/agents/nix-module-specialist.md`
- `.cursor/agents/nix-profile-specialist.md`
- `.cursor/claude-cursor-rules-02.md`
- `.agent/flake-refactor.md`
- `.claude/agents/flake-refactor.md`
- `.cursor/agents/flake-refactor.md`
- `.agent/sway-specialist.md`
- `.claude/agents/sway-specialist.md`

#### 4. Configuration Files (9 files)
- `flake.ORIGINAL.nix`
- `lib/flake-base.nix`
- `user/app/terminal/alacritty.nix`
- `user/app/terminal/foot.nix`
- `user/app/terminal/kitty.nix`
- `user/app/terminal/tmux.nix`
- `user/shell/sh.nix`
- `user/wm/hyprland/hyprland.nix`
- `user/wm/sway/default.nix`

### Example Changes by File Type

#### system/bin/phoenix.nix → system/bin/aku.nix
**Before:**
```nix
# phoenix CLI - system management tool
```

**After:**
```nix
# aku CLI - system management tool
```

#### Documentation Files
**Before:**
```markdown
Apply changes using `phoenix sync` or `./install.sh`
```

**After:**
```markdown
Apply changes using `aku sync` or `./install.sh`
```

#### Configuration Files (sh.nix)
**Before:**
```nix
alias phs="phoenix sync"
alias phb="phoenix build"
```

**After:**
```nix
alias aks="aku sync"
alias akb="aku build"
```

## Conflict Verification

### Current Status: ✅ NO CONFLICTS FOUND

1. **No existing "aku" command**: `grep -r "aku" --include="*.nix" --include="*.md" --include="*.sh"` returns 0 results
2. **No nixpkgs package named "aku"**: Verified via `nix search nixpkgs aku`
3. **PATH conflicts**: No system command named "aku" exists

### Post-Rename Verification Required
After rename, verify:
- [ ] No remaining "phoenix" references (except in git history)
- [ ] `aku` command resolves correctly
- [ ] All aliases work as expected
- [ ] Documentation is consistent

## Rename Procedure

### Phase 1: Rename Main Binary File
```bash
cd /home/akunito/.dotfiles
git mv system/bin/phoenix.nix system/bin/aku.nix
```

### Phase 2: Update All References

#### Step 1: Update lib/flake-base.nix
Replace phoenix.nix import with aku.nix import:
```nix
# Before:
../../system/bin/phoenix.nix

# After:
../../system/bin/aku.nix
```

#### Step 2: Update Documentation Files (11 files)
Replace all instances of:
- `phoenix` → `aku`
- `phoenix sync` → `aku sync`
- `phoenix build` → `aku build`
- `phoenix rollback` → `aku rollback`
- `phoenix test` → `aku test`

Files to update:
1. `.claude/AGENTS.md`
2. `CLAUDE.md`
3. `README.md`
4. `docs/00_ROUTER.md`
5. `docs/01_CATALOG.md`
6. `docs/future/migrate-agents.md`
7. `docs/nix-modules/dotfiles-management.md`
8. `docs/nix-modules/home-manager.md`
9. `docs/system-modules/system-applications.md`
10. `docs/user-modules/shell.md`
11. `docs/user-modules/tmux.md`

#### Step 3: Update Agent Context Files (12 files)
Same replacements as documentation files.

Files to update:
1. `.agent/nix-module-specialist.md`
2. `.agent/nix-profile-specialist.md`
3. `.claude/agents/nix-module-specialist.md`
4. `.claude/agents/nix-profile-specialist.md`
5. `.cursor/agents/nix-module-specialist.md`
6. `.cursor/agents/nix-profile-specialist.md`
7. `.cursor/claude-cursor-rules-02.md`
8. `.agent/flake-refactor.md`
9. `.claude/agents/flake-refactor.md`
10. `.cursor/agents/flake-refactor.md`
11. `.agent/sway-specialist.md`
12. `.claude/agents/sway-specialist.md`

#### Step 4: Update Configuration Files (8 files)
Update shell aliases and references:
- `phs` → `aks` (aku sync)
- `phb` → `akb` (aku build)
- `phr` → `akr` (aku rollback)
- `pht` → `akt` (aku test)
- `phoenix` → `aku`

Files to update:
1. `flake.ORIGINAL.nix`
2. `user/app/terminal/alacritty.nix`
3. `user/app/terminal/foot.nix`
4. `user/app/terminal/kitty.nix`
5. `user/app/terminal/tmux.nix`
6. `user/shell/sh.nix`
7. `user/wm/hyprland/hyprland.nix`
8. `user/wm/sway/default.nix`

#### Step 5: Update system/bin/aku.nix Internal References
Update any internal comments or strings that reference "phoenix":
```nix
# Before:
description = "Phoenix CLI - system management tool";

# After:
description = "Aku CLI - system management tool";
```

### Phase 3: Verification

#### Automated Checks
```bash
# 1. Verify no remaining "phoenix" references (excluding git history)
grep -r "phoenix" --include="*.nix" --include="*.md" --include="*.sh" | grep -v ".git"

# 2. Check flake
nix flake check

# 3. Verify aku command exists after rebuild
which aku

# 4. Test aku commands
aku --help
aku sync --help
aku build --help
```

#### Manual Verification
- [ ] Open README.md - verify all commands show "aku"
- [ ] Check CLAUDE.md - verify agent rules reference "aku"
- [ ] Review shell aliases in sh.nix
- [ ] Test `aks` alias after system rebuild
- [ ] Verify tmux keybindings reference correct command

### Phase 4: Commit Changes
```bash
git add -A
git commit -m "Rename phoenix command to aku

- Renamed system/bin/phoenix.nix → system/bin/aku.nix
- Updated all references across 33 files
- Updated shell aliases: phs→aks, phb→akb, phr→akr, pht→akt
- Updated documentation and agent context files
- Total: 128 occurrences replaced

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

## Testing Plan

### Pre-Deployment Testing
1. **Dry run flake check**: `nix flake check --dry-run`
2. **Build without activation**: `aku build` (should work after first rebuild)
3. **Verify help output**: `aku --help`

### Post-Deployment Testing
1. **System Rebuild**: `aku sync` or `./install.sh`
2. **Test all subcommands**:
   ```bash
   aku sync
   aku build
   aku rollback
   aku test
   ```
3. **Test shell aliases**:
   ```bash
   aks  # Should run 'aku sync'
   akb  # Should run 'aku build'
   akr  # Should run 'aku rollback'
   akt  # Should run 'aku test'
   ```
4. **Verify PATH**: `which aku` should return `/run/current-system/sw/bin/aku`
5. **Test tmux bindings**: Verify `<prefix>-r` still works for system rebuild

### Integration Testing
- [ ] SSH into remote systems - verify aku command available
- [ ] Test on different profiles (DESK, LAPTOP, VMHOME)
- [ ] Verify documentation accuracy (follow a doc example using aku)

## Rollback Plan

### If Issues Arise During Rename

#### Option 1: Git Revert (Recommended)
```bash
# If committed
git revert HEAD

# If not committed
git reset --hard HEAD
git clean -fd
```

#### Option 2: Manual Rollback
```bash
# Rename file back
git mv system/bin/aku.nix system/bin/phoenix.nix

# Restore from git
git checkout HEAD -- lib/flake-base.nix
git checkout HEAD -- user/shell/sh.nix
# ... restore other files as needed
```

#### Option 3: Stash and Review
```bash
# Stash all changes
git stash

# Review what went wrong
nix flake check

# Apply stash when ready or drop
git stash drop  # to discard
git stash pop   # to reapply
```

### Recovery Commands
If system is broken after rename:
```bash
# Use old command if still in PATH
phoenix rollback

# Or use install.sh directly
./install.sh

# Or rebuild from previous generation
sudo nixos-rebuild switch --rollback
```

## Special Considerations

### 1. Git History
- Old commits will still reference "phoenix" - this is expected and acceptable
- Git blame will show the rename commit clearly
- No need to rewrite history

### 2. External Documentation
If there are:
- Blog posts
- External wikis
- Shared documentation outside this repo

These will need separate updates (out of scope for this plan).

### 3. User Muscle Memory
Users familiar with "phoenix" commands will need to update their habits:
- Consider adding temporary alias `phoenix` → `aku` in sh.nix for transition period
- Document the change in release notes
- Update any personal scripts that call phoenix

### 4. Backup Consideration
Before executing the rename:
```bash
# Create a backup branch
git checkout -b backup-before-aku-rename
git checkout main
```

## Execution Checklist

- [ ] Review this plan thoroughly
- [ ] Create backup branch
- [ ] Phase 1: Rename main binary file
- [ ] Phase 2: Update all references (33 files)
- [ ] Phase 3: Run verification checks
- [ ] Phase 4: Commit changes
- [ ] Run pre-deployment tests
- [ ] Execute system rebuild with `./install.sh`
- [ ] Run post-deployment tests
- [ ] Run integration tests
- [ ] Mark as complete or execute rollback if needed

## Timeline

Estimated time: 30-45 minutes
- Rename and updates: 15-20 minutes
- Verification: 10-15 minutes
- Testing: 10-15 minutes

## Sign-off

**Plan Status**: ⏳ Awaiting Review

**Reviewed By**: [User]
**Approved By**: [User]
**Executed By**: [Agent/User]
**Date**: [YYYY-MM-DD]

---

**Note**: This is a comprehensive plan. Review carefully before execution. All changes are reversible via git.
