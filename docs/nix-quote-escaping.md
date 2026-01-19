---
id: docs.nix-quote-escaping
summary: Guide to properly escaping quotes and special characters in Nix strings to avoid common syntax errors.
tags: [nix, nixos, home-manager, syntax, escaping, quotes, strings, troubleshooting]
related_files:
  - docs/nix-quote-escaping.md
  - user/app/terminal/tmux.nix
key_files:
  - docs/nix-quote-escaping.md
activation_hints:
  - When encountering "syntax error, unexpected invalid token" in Nix files
  - When working with nested quotes in tmux configs or shell commands
  - When embedding shell scripts in Nix strings
---

# Nix Quote Escaping Guide

## Common Problem

When working with Nix strings, especially in `extraConfig` sections or when embedding shell commands, you'll often encounter errors like:

```
error: syntax error, unexpected invalid token, expecting '.' or '='
```

This typically happens when quotes are not properly escaped in Nix strings.

## Nix String Types

Nix has two main string types:

1. **Double-quoted strings** (`"..."`) - Support escape sequences and interpolation
2. **Single-quoted strings** (`''...''`) - Multi-line strings, less escaping needed

## Escaping Rules

### In Double-Quoted Strings (`"..."`)

- Use `\"` to escape a double quote
- Use `\\` to escape a backslash
- Use `\n` for newline, `\t` for tab, etc.

**Example:**
```nix
extraConfig = ''
  bind-key x "send-keys \"Hello World\""
'';
```

### In Multi-Line Strings (`''...''`)

- Use `''` to escape a single quote (but this is rare)
- Use `\` to escape special characters
- Double quotes don't need escaping inside `''...''`

**Example:**
```nix
extraConfig = ''
  bind-key x "send-keys 'Hello World'"
'';
```

## Common Patterns

### Pattern 1: Shell Command with Quotes

**Problem:**
```nix
# ❌ This will fail
extraConfig = ''
  set-hook -g session-closed 'run-shell "echo hello"'
'';
```

**Solution:**
```nix
# ✅ Use double quotes for the outer string, escape inner quotes
extraConfig = ''
  set-hook -g session-closed "run-shell \"echo hello\""
'';
```

### Pattern 2: Nested Shell Commands

**Problem:**
```nix
# ❌ This will fail
extraConfig = ''
  set-hook -g session-closed 'run-shell "$(tmux show-options -g @path)"'
'';
```

**Solution:**
```nix
# ✅ Escape the $ and quotes properly
extraConfig = ''
  set-hook -g session-closed "run-shell 'tmux show-options -g @path 2>/dev/null | awk \"{print \\\$2}\" | xargs -r sh'"
'';
```

### Pattern 3: Complex Shell Pipeline

**Problem:**
```nix
# ❌ This will fail
extraConfig = ''
  bind-key x run-shell 'tmux show-options -g @resurrect-save-script-path | awk '{print $2}''
'';
```

**Solution:**
```nix
# ✅ Use double quotes and escape properly
extraConfig = ''
  bind-key x run-shell "tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \\\$2}\" | xargs -r sh"
'';
```

## Best Practices

1. **Prefer multi-line strings** (`''...''`) for complex configurations
2. **Use double quotes inside multi-line strings** when possible (they don't need escaping)
3. **Escape `$` as `\$`** when you want a literal dollar sign (not interpolation)
4. **Test incrementally** - add complex strings piece by piece
5. **Use `nix-instantiate --parse`** to check syntax before building

## Debugging Tips

### Check Syntax

```bash
# Parse a Nix file to check for syntax errors
nix-instantiate --parse file.nix
```

### Test Configuration

```bash
# For Home Manager configs
cd /home/akunito/.dotfiles && ./sync-user.sh

# Check for errors in the output
```

### Common Error Messages

- `syntax error, unexpected invalid token` - Usually quote escaping issue
- `undefined variable` - Variable not in scope or typo
- `unexpected EOF` - Missing closing quote or bracket

## Real-World Example: Tmux Hooks

Here's a working example from the tmux configuration:

```nix
extraConfig = ''
  # Save on session close/detach to prevent data loss
  # Hook to save when session is closed (all windows in session are closed)
  set-hook -g session-closed "run-shell 'tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \\\$2}\" | xargs -r sh'"
  # Hook to save when client detaches (user detaches from tmux)
  set-hook -g client-detached "run-shell 'tmux show-options -g @resurrect-save-script-path 2>/dev/null | awk \"{print \\\$2}\" | xargs -r sh'"
'';
```

**Breakdown:**
- Outer: `''...''` (multi-line string)
- Middle: `"..."` (tmux command string)
- Inner: `'...'` (shell command string)
- Deep: `\"...\"` (escaped quotes for awk pattern)
- Deepest: `\\\$` (escaped backslash and dollar for awk variable)

## Quick Reference

| What you want | In `"..."` | In `''...''` |
|---------------|------------|--------------|
| Literal `"` | `\"` | `"` |
| Literal `$` | `\$` | `\$` |
| Literal `\` | `\\` | `\` |
| Newline | `\n` | Actual newline |
| Single quote | `'` | `''` (rare) |

## Related Documentation

- [Nix Manual - Strings](https://nixos.org/manual/nix/stable/language/values.html#type-string)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Tmux Configuration](../user-modules/tmux.md)
