---
id: shell-multiline-input
summary: Multi-line shell input with Shift+Enter configuration
tags: [shell, zsh, terminal, keyboard, keybindings]
related_files:
  - lib/defaults.nix
  - profiles/DESK-config.nix
  - user/app/terminal/kitty.nix
  - user/app/terminal/alacritty.nix
  - user/app/terminal/tmux.nix
  - ~/.Xresources
---

# Multi-line Shell Input (Shift+Enter)

## Overview

This configuration enables multi-line command editing in the shell using **Shift+Enter** to insert newlines. This allows you to write complex multi-line commands without executing them prematurely.

## How It Works

The feature requires configuration at three levels:
1. **Terminal**: Send a distinct escape sequence for Shift+Enter
2. **Tmux**: Pass through the escape sequence (extended keys support)
3. **Zsh**: Bind the escape sequence to insert a newline

## Components

### 1. Zsh Configuration

Location: `profiles/DESK-config.nix` (and other profiles)

```nix
zshinitContent = ''
  # Multi-line editing with Shift+Enter
  insert-newline() {
    LBUFFER="$LBUFFER"$'\n'
  }
  zle -N insert-newline

  # Bind Shift+Enter to insert newline (various terminal escape sequences)
  bindkey '\e[13;2u' insert-newline    # Kitty, Alacritty (CSI u mode)
  bindkey '\e[27;2;13~' insert-newline # Some other terminals
  bindkey '\eOM' insert-newline        # Alternative sequence
'';
```

**Key points:**
- Creates a custom ZLE widget `insert-newline` that appends a newline to the current buffer
- Binds multiple escape sequences to handle different terminals
- The primary sequence `\e[13;2u` is CSI u encoded (modern terminal standard)

### 2. Kitty Configuration

Location: `user/app/terminal/kitty.nix`

```nix
programs.kitty.keybindings = {
  # Multi-line input: Shift+Enter sends CSI u encoded escape sequence
  "shift+enter" = "send_text all \\x1b[13;2u";
};
```

### 3. Alacritty Configuration

Location: `user/app/terminal/alacritty.nix`

```nix
keyboard = {
  bindings = [
    # Multi-line input: Shift+Enter sends CSI u encoded escape sequence
    { key = "Return"; mods = "Shift"; chars = "\\u001b[13;2u"; }
  ];
};
```

### 4. Tmux Configuration

Location: `user/app/terminal/tmux.nix`

```nix
extraConfig = ''
  # Enable extended keys (tmux 3.2+) for proper Shift+Enter handling
  set -s extended-keys on
  set -as terminal-features 'xterm*:extkeys'
'';
```

**Key points:**
- Enables tmux 3.2+ extended keys support
- Allows tmux to pass through CSI u encoded sequences
- Without this, tmux would swallow the escape sequence

### 5. XTerm Configuration

Location: `user/app/terminal/xterm.nix`

```nix
xresources.properties = {
  # Dark mode colors
  "XTerm*background" = "#1c1c1c";
  "XTerm*foreground" = "#d0d0d0";
  # ... (see xterm.nix for full color scheme)

  # Font settings
  "XTerm*faceName" = "JetBrainsMono Nerd Font Mono";
  "XTerm*faceSize" = 12;
};

xresources.extraConfig = ''
  ! Shift+Enter keybinding for multi-line input
  XTerm*VT100.translations: #override \n\
  	Shift <Key>Return: string(0x1b) string("[13;2u")
'';
```

**Note:** XTerm configuration is managed declaratively by Home Manager. The `~/.Xresources` file is automatically generated and loaded.

## Usage

1. Start typing a command
2. Press **Shift+Enter** to insert a newline
3. Continue typing on the next line
4. Press **Enter** (without Shift) to execute the command

Example:
```bash
$ echo "first line"<Shift+Enter>
> echo "second line"<Shift+Enter>
> echo "third line"<Enter>
first line
second line
third line
```

## Supported Terminals

| Terminal | Configuration | Status |
|----------|--------------|--------|
| Kitty | Automatic (NixOS) | ✅ Working |
| Alacritty | Automatic (NixOS) | ✅ Working |
| XTerm | Manual (.Xresources) | ✅ Working |
| Other terminals | May need custom config | ⚠️ Not tested |

## Troubleshooting

### Shift+Enter doesn't work in new profile

If you create a new profile and Shift+Enter doesn't work:

1. Check if the profile has its own `zshinitContent` that overrides defaults
2. Add the `insert-newline` widget to that profile's `zshinitContent`
3. Run `./sync-user.sh` to apply changes

Example for new profiles:
```nix
zshinitContent = ''
  # ... existing keybindings ...

  # Multi-line editing with Shift+Enter
  insert-newline() {
    LBUFFER="$LBUFFER"$'\n'
  }
  zle -N insert-newline
  bindkey '\e[13;2u' insert-newline
  bindkey '\e[27;2;13~' insert-newline
  bindkey '\eOM' insert-newline
'';
```

### Works in Kitty/Alacritty but not in tmux

1. Check tmux version: `tmux -V` (needs 3.2+)
2. Verify extended keys are enabled:
   ```bash
   tmux show-options -s | grep extended-keys
   # Should show: extended-keys on
   ```
3. Kill and restart tmux server:
   ```bash
   tmux kill-server
   systemctl --user restart tmux-server
   ```

### Doesn't work in XTerm

1. Verify `.Xresources` file exists and has the Shift+Enter binding
2. Load the resources: `xrdb ~/.Xresources`
3. Open a **NEW** xterm window (existing windows won't pick up changes)
4. Test with `cat -v` to see what escape sequence is sent

## Architecture Decision

**Why not in lib/defaults.nix?**

The `insert-newline` widget is added to individual profile `zshinitContent` rather than `lib/defaults.nix` because many profiles override `zshinitContent` completely, which would ignore the defaults. Future improvement: make profiles append to defaults rather than replace.

## Related Documentation

- Zsh Line Editor (ZLE): http://zsh.sourceforge.net/Doc/Release/Zsh-Line-Editor.html
- CSI u keyboard protocol: https://sw.kovidgoyal.net/kitty/keyboard-protocol/
- Tmux extended keys: https://github.com/tmux/tmux/wiki/Modifier-Keys

## Git Commit

Changes introduced in commit: [Multi-line shell input with Shift+Enter]

Modified files:
- `lib/defaults.nix` - Added insert-newline widget (for future profiles)
- `profiles/DESK-config.nix` - Added insert-newline widget to DESK profile
- `user/app/terminal/kitty.nix` - Added Shift+Enter keybinding
- `user/app/terminal/alacritty.nix` - Added Shift+Enter keybinding
- `user/app/terminal/tmux.nix` - Added extended-keys support
- `user/app/terminal/xterm.nix` - New module for declarative XTerm configuration
- `user/wm/sway/default.nix` - Import xterm.nix module
- `docs/user-modules/shell-multiline-input.md` - Full documentation

**Note:** XTerm configuration is now fully declarative via Home Manager. The `~/.Xresources` file is automatically generated from `xterm.nix`.
