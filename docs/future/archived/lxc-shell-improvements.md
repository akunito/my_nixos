# LXC Shell Improvements - Color and Cursor Visibility

**Created:** 2026-01-29
**Status:** Analysis & Solution
**Priority:** Medium (usability improvement)

## Problem Statement

When connecting to LXC containers via SSH:
1. **No colors** - Terminal output lacks syntax highlighting and colored prompts
2. **Invisible cursor** - Cursor not visible while typing (especially in Claude Code)

## Current LXC Shell Configuration

### Existing Setup (profiles/proxmox-lxc/home.nix)

```nix
programs.zsh = {
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;  # ✅ Already enabled
  enableCompletion = true;
  initContent = userSettings.zshinitContent;  # Custom prompt from profile config
};

programs.bash = {
  enable = true;
  enableCompletion = true;  # ❌ No colors configured
};
```

### Current Profile Prompts

**LXC-base-config.nix:**
```nix
zshinitContent = ''
  PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
  %F{green}→%f "
  RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
  [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
'';
```

**LXC_HOME-config.nix:**
```nix
zshinitContent = ''
  PROMPT=" ◉ %U%F{red}%n%f%u@%U%F{red}%m%f%u:%F{yellow}~%f
  %F{green}→%f "
  RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
  [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
'';
```

## Root Causes Analysis

### 1. TERM Variable Not Propagated via SSH

**Issue:** SSH server doesn't accept TERM environment variable from client

**Evidence:**
- `system/security/sshd.nix` has no `AcceptEnv` configuration
- Default SSH config only accepts `LANG LC_*` variables
- TERM defaults to `dumb` or basic `xterm` instead of `xterm-256color`

**Impact:**
- Colors disabled in terminal
- Cursor visibility issues
- Poor readline/zsh-autosuggestions rendering

### 2. Missing TERM Export in Shell Init

**Issue:** Shell doesn't explicitly set TERM to a color-capable terminal

**Current behavior:**
```nix
[ $TERM = "dumb" ] && unsetopt zle && PS1='$ '  # Only handles dumb terminal
```

**Needed:**
```bash
export TERM=xterm-256color  # Explicitly set color-capable terminal
```

### 3. Bash Has No Color Configuration

**Issue:** Bash (fallback shell) has no PS1 colors or aliases

**Current:**
```nix
programs.bash = {
  enable = true;
  enableCompletion = true;  # No colors, no aliases, no prompt customization
};
```

## Existing Solutions in the Project

### user/shell/sh.nix (Full Desktop Shell Config)

```nix
programs.zsh = {
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  enableCompletion = true;
  shellAliases = basicAliases;  # Colored ls, cat->bat, etc.
  initContent = userSettings.zshinitContent + "\n" + "clear && disfetch";
};

programs.bash = {
  enable = true;
  enableCompletion = true;
  shellAliases = basicAliases;  # ✅ Has colors via aliases
};

home.packages = with pkgs; [
  disfetch onefetch bat eza bottom fd bc atuin  # Heavy packages
];
```

**Packages overhead:**
- `disfetch`, `onefetch` - fancy fetch tools (not needed for server)
- `bat` - syntax-highlighted cat (nice-to-have)
- `eza` - modern ls replacement (nice-to-have)
- `bottom` - modern htop (redundant with btop)

### tmux.nix (Terminal Configuration)

```nix
terminal = "screen-256color";  # ✅ Proper 256-color support
set -ga terminal-overrides ",xterm-256color:Tc"  # True color support
```

## Proposed Solutions (Minimal Overhead)

### Solution 1: SSH TERM Propagation (RECOMMENDED - Zero Overhead)

**File:** `system/security/sshd.nix`

```nix
services.openssh = {
  enable = true;
  openFirewall = true;
  settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    AllowUsers = [ userSettings.username ];
  };
  extraConfig = ''
    # Accept TERM and other safe environment variables from SSH clients
    AcceptEnv LANG LC_* TERM COLORTERM
  '';
};
```

**Benefits:**
- ✅ Zero package overhead
- ✅ Fixes color issues immediately
- ✅ Fixes cursor visibility
- ✅ Works for all SSH clients
- ✅ No profile-specific changes needed

**Impact:**
- Adds ~50 bytes to sshd_config
- No runtime overhead

### Solution 2: Explicit TERM in Shell Init (Fallback)

**File:** `profiles/LXC-base-config.nix`

```nix
zshinitContent = ''
  # Set proper terminal type for colors and cursor
  export TERM=''${TERM:-xterm-256color}
  export COLORTERM=truecolor

  PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
  %F{green}→%f "
  RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
  [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
'';
```

**Benefits:**
- ✅ Zero package overhead
- ✅ Works even if SSH doesn't propagate TERM
- ✅ Ensures consistent terminal type

**Impact:**
- Adds ~60 bytes to shell init
- No runtime overhead

### Solution 3: Lightweight Shell Aliases (Optional)

**File:** `profiles/proxmox-lxc/home.nix`

Add minimal color aliases without heavy packages:

```nix
programs.zsh = {
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  enableCompletion = true;
  initContent = userSettings.zshinitContent;

  # Lightweight aliases (no package dependencies)
  shellAliases = {
    ll = "ls -la --color=auto";
    ls = "ls --color=auto";
    grep = "grep --color=auto";
    diff = "diff --color=auto";
  };
};

programs.bash = {
  enable = true;
  enableCompletion = true;

  # Same lightweight aliases for bash
  shellAliases = {
    ll = "ls -la --color=auto";
    ls = "ls --color=auto";
    grep = "grep --color=auto";
    diff = "diff --color=auto";
  };
};
```

**Benefits:**
- ✅ Zero package overhead (uses coreutils already installed)
- ✅ Basic color support for common commands
- ✅ Works in both zsh and bash

**Impact:**
- Adds ~200 bytes to shell config
- No runtime overhead

### Solution 4: Reuse Full Shell Config (NOT RECOMMENDED)

**Option:** Import `user/shell/sh.nix` for LXC profiles

**Pros:**
- Full feature parity with desktop
- Consistent experience across all profiles

**Cons:**
- ❌ Adds ~50MB packages (disfetch, onefetch, bat, eza, bottom)
- ❌ Increased build time
- ❌ Unnecessary for headless servers
- ❌ Against LXC lightweight philosophy

**Verdict:** Not worth the overhead for container use case

## Recommended Implementation

### Phase 1: Fix SSH TERM Propagation (Immediate)

**Change 1:** Update `system/security/sshd.nix`

```nix
services.openssh = {
  # ... existing config ...
  extraConfig = ''
    # Accept TERM and safe environment variables from SSH clients
    AcceptEnv LANG LC_* TERM COLORTERM
  '';
};
```

**Testing:**
```bash
# From client
ssh user@lxc-container
echo $TERM  # Should show xterm-256color or whatever client uses
```

### Phase 2: Add Fallback TERM Export (Belt & Suspenders)

**Change 2:** Update `profiles/LXC-base-config.nix`

```nix
zshinitContent = ''
  # Ensure proper terminal type for colors and cursor visibility
  export TERM=''${TERM:-xterm-256color}
  export COLORTERM=truecolor

  PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
  %F{green}→%f "
  RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
  [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
'';
```

**Same for `profiles/LXC_HOME-config.nix`** (red prompt variant)

### Phase 3: Add Lightweight Color Aliases (Optional Enhancement)

**Change 3:** Update `profiles/proxmox-lxc/home.nix`

```nix
programs.zsh = {
  enable = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;
  enableCompletion = true;
  initContent = userSettings.zshinitContent;

  shellAliases = {
    ll = "ls -la --color=auto";
    ls = "ls --color=auto";
    grep = "grep --color=auto";
    diff = "diff --color=auto";
    ip = "ip -color=auto";
  };
};

programs.bash = {
  enable = true;
  enableCompletion = true;
  shellAliases = {
    ll = "ls -la --color=auto";
    ls = "ls --color=auto";
    grep = "grep --color=auto";
    diff = "diff --color=auto";
    ip = "ip -color=auto";
  };
};
```

## Overhead Analysis

### Solution Comparison

| Solution | Package Overhead | Build Time | Runtime Memory | Config Size |
|----------|-----------------|------------|----------------|-------------|
| SSH AcceptEnv | 0 bytes | +0s | 0 KB | +50 bytes |
| TERM export | 0 bytes | +0s | 0 KB | +60 bytes |
| Lightweight aliases | 0 bytes | +0s | 0 KB | +200 bytes |
| **Total (Recommended)** | **0 bytes** | **+0s** | **0 KB** | **+310 bytes** |
| Full sh.nix import | ~50 MB | +30s | ~5 MB | +2 KB |

### Impact Assessment

**Recommended solution (Phases 1-3):**
- ✅ Zero package overhead
- ✅ Zero build time increase
- ✅ Zero runtime overhead
- ✅ Minimal config increase (~310 bytes)
- ✅ Fixes both color and cursor issues
- ✅ Works across all LXC profiles
- ✅ No changes to existing architecture

**Rejected solution (Full import):**
- ❌ +50MB packages
- ❌ +30s build time
- ❌ +5MB runtime memory
- ❌ Against LXC lightweight design

## Testing Procedure

### Before Changes

```bash
# SSH into LXC
ssh user@lxc-container

# Check TERM
echo $TERM  # Likely shows 'dumb' or basic 'xterm'

# Check colors
ls --color=auto  # May show no colors

# Check cursor (in Claude Code)
claude  # Cursor may be invisible while typing
```

### After Changes

```bash
# Rebuild and deploy
cd ~/.dotfiles
./install.sh ~/.dotfiles LXC_HOME -s -u

# SSH into LXC
ssh user@lxc-container

# Check TERM
echo $TERM  # Should show 'xterm-256color'
echo $COLORTERM  # Should show 'truecolor'

# Check colors
ls  # Should show colors via alias
ll  # Should show colors

# Check prompt colors
pwd  # Prompt should show cyan user@host, yellow path, green arrow

# Check cursor (in Claude Code)
claude  # Cursor should be visible while typing
```

### Verification Checklist

- [ ] `$TERM` shows color-capable terminal (xterm-256color, screen-256color, etc.)
- [ ] `$COLORTERM` is set to 'truecolor'
- [ ] Zsh prompt shows colors (cyan, yellow, green, red)
- [ ] `ls` shows colored output
- [ ] Cursor is visible in interactive applications
- [ ] Claude Code shows cursor while typing
- [ ] Zsh autosuggestions render properly
- [ ] No package overhead added

## Impact on Other Profiles

### Profiles NOT Affected

- ✅ DESK-config.nix - Uses full user/shell/sh.nix (no changes)
- ✅ LAPTOP-base.nix - Uses full user/shell/sh.nix (no changes)
- ✅ VMHOME-config.nix - Uses full user/shell/sh.nix (no changes)
- ✅ WSL-config.nix - Uses full user/shell/sh.nix (no changes)

### Profiles Modified

- 🔧 system/security/sshd.nix - AcceptEnv applies to ALL profiles (safe)
- 🔧 profiles/LXC-base-config.nix - Only affects LXC containers
- 🔧 profiles/LXC_HOME-config.nix - Only affects LXC_HOME
- 🔧 profiles/proxmox-lxc/home.nix - Only affects LXC containers

**Safety:** Changes are isolated to LXC profiles and SSH daemon (which improves all profiles)

## Alternative Approaches Considered

### 1. Use tmux by Default

**Idea:** Auto-start tmux on SSH login

```nix
programs.zsh.initExtra = ''
  if [ -z "$TMUX" ] && [ -n "$SSH_CONNECTION" ]; then
    tmux attach-session -t ssh_tmux || tmux new-session -s ssh_tmux
  fi
'';
```

**Pros:**
- Tmux handles TERM properly (screen-256color)
- Session persistence
- Better multiplexing

**Cons:**
- ❌ Overhead for simple SSH sessions
- ❌ Not always desired behavior
- ❌ Doesn't fix root cause

**Verdict:** Keep as optional user preference, not default

### 2. Install Fancy Shell Packages

**Idea:** Install bat, eza, bottom in LXC profiles

**Pros:**
- Better user experience
- Consistent with desktop profiles

**Cons:**
- ❌ ~50MB package overhead
- ❌ Against lightweight LXC philosophy
- ❌ Not necessary for server containers

**Verdict:** Rejected - stick to lightweight approach

### 3. Create Conditional Shell Module

**Idea:** Create `user/shell/sh-light.nix` for servers

```nix
# user/shell/sh-light.nix
{
  programs.zsh = {
    # ... minimal config ...
    shellAliases = lightweightAliases;  # No bat, eza
  };
  home.packages = [ ];  # No fancy packages
}
```

**Pros:**
- Reusable across server profiles
- Maintains code organization

**Cons:**
- ❌ Creates duplicate code (sh.nix vs sh-light.nix)
- ❌ Maintenance burden
- ❌ Current solution is already lightweight enough

**Verdict:** Not worth the complexity - keep inline config

## Conclusion

**Recommended approach:**
1. ✅ Add `AcceptEnv TERM COLORTERM` to SSH daemon (affects all profiles, improves all)
2. ✅ Add `export TERM=${TERM:-xterm-256color}` to LXC shell init (fallback)
3. ✅ Add lightweight color aliases to LXC (optional enhancement)

**Total overhead:** ~310 bytes of config, zero packages, zero runtime cost

**Benefits:**
- Fixes color display issues
- Fixes cursor visibility
- Improves usability in Claude Code
- No impact on container performance
- No architectural changes
- Maintains LXC lightweight philosophy

**Next steps:**
1. Implement Phase 1 (SSH AcceptEnv)
2. Test SSH color propagation
3. Implement Phase 2 (TERM export) if needed
4. Implement Phase 3 (aliases) for enhanced UX
5. Update LXC documentation
