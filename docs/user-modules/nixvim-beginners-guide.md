---
id: user-modules.nixvim-beginners-guide
summary: Beginner's guide to using NixVim and Avante, including Vim navigation basics for users new to Vim/Neovim.
tags: [nixvim, neovim, vim, beginners, tutorial, avante, user-modules]
related_files:
  - user/app/nixvim/**
  - docs/user-modules/nixvim.md
  - docs/user-modules/nixvim-beginners-guide.md
key_files:
  - docs/user-modules/nixvim-beginners-guide.md
activation_hints:
  - If you're new to Vim/Neovim and want to learn how to use NixVim
  - If you want to learn how to use Avante AI assistant
---

# NixVim Beginner's Guide

Complete step-by-step guide for beginners to learn Vim navigation, use NixVim, and leverage Avante AI assistant. This guide assumes no prior Vim knowledge.

## Table of Contents

- [Getting Started](#getting-started)
- [Vim Basics: Understanding Modes](#vim-basics-understanding-modes)
- [Essential Vim Commands](#essential-vim-commands)
- [Opening and Editing Files](#opening-and-editing-files)
- [Saving and Quitting](#saving-and-quitting)
- [Using NixVim Features](#using-nixvim-features)
- [Using Avante AI Assistant](#using-avante-ai-assistant)
- [Common Tasks](#common-tasks)
- [Practice Exercises](#practice-exercises)
- [Getting Help](#getting-help)
- [Quick Reference Card](#quick-reference-card)

## Getting Started

### Launching Neovim

Open a terminal and type:

```bash
nvim
```

Or open a specific file:

```bash
nvim filename.txt
```

You'll see the Neovim interface. Don't panic if it looks different from other editors!

### First Thing to Know: How to Quit

**IMPORTANT**: Before learning anything else, memorize how to exit Vim:

1. Press `Esc` (to ensure you're in Normal mode)
2. Type `:q` and press `Enter` (to quit)
3. If you have unsaved changes, use `:q!` to quit without saving

**Remember**: `Esc` then `:q` then `Enter` = quit

## Vim Basics: Understanding Modes

Vim has different **modes** for different tasks. This is the key concept that makes Vim powerful but initially confusing.

### The Three Essential Modes

1. **Normal Mode** (default)
   - For navigation and commands
   - You start here when you open Vim
   - Press `Esc` to return here from any other mode
   - **Think of it as "command mode"**

2. **Insert Mode**
   - For typing text (like a normal editor)
   - Press `i` to enter Insert mode
   - You'll see `-- INSERT --` at the bottom
   - Press `Esc` to return to Normal mode

3. **Visual Mode**
   - For selecting text
   - Press `v` to enter Visual mode
   - Use arrow keys to select
   - Press `Esc` to cancel selection

### Mode Indicator

Look at the bottom of the screen:
- `-- INSERT --` = You're in Insert mode (typing mode)
- `-- VISUAL --` = You're in Visual mode (selection mode)
- Nothing shown = You're in Normal mode (command mode)

**Golden Rule**: When in doubt, press `Esc` to return to Normal mode.

## Essential Vim Commands

### Movement (Normal Mode)

Vim uses keyboard keys for movement (no mouse needed):

| Key | Action |
|-----|--------|
| `h` | Move left |
| `j` | Move down |
| `k` | Move up |
| `l` | Move right |
| `w` | Move forward one word |
| `b` | Move backward one word |
| `0` (zero) | Move to beginning of line |
| `$` | Move to end of line |
| `gg` | Go to top of file |
| `G` | Go to bottom of file |
| `Ctrl+d` | Scroll down half page |
| `Ctrl+u` | Scroll up half page |

**Tip**: Think of `h`, `j`, `k`, `l` as arrow keys on your keyboard (left, down, up, right).

### Basic Editing

| Command | Action |
|---------|--------|
| `i` | Enter Insert mode (start typing) |
| `a` | Enter Insert mode after cursor |
| `o` | Open new line below and enter Insert mode |
| `O` | Open new line above and enter Insert mode |
| `x` | Delete character under cursor |
| `dd` | Delete entire line |
| `yy` | Copy (yank) entire line |
| `p` | Paste after cursor |
| `P` | Paste before cursor |
| `u` | Undo |
| `Ctrl+r` | Redo |

### Combining Commands

Vim commands can be combined with numbers:

- `3dd` = Delete 3 lines
- `5j` = Move down 5 lines
- `2w` = Move forward 2 words
- `10x` = Delete 10 characters

## Opening and Editing Files

### Opening a File

**From terminal**:
```bash
nvim myfile.txt
```

**From inside Neovim** (Normal mode):
1. Press `Esc` (ensure Normal mode)
2. Type `:e filename.txt` and press `Enter`
3. Or use Telescope: Press `Ctrl+p` (see below)

### Creating a New File

1. Open Neovim: `nvim`
2. Press `i` to enter Insert mode
3. Type your content
4. Press `Esc` to return to Normal mode
5. Type `:w filename.txt` and press `Enter` to save

### Editing Existing Text

1. **Move to where you want to edit**:
   - Use `h`, `j`, `k`, `l` or arrow keys
   - Or click with mouse (if enabled)

2. **Enter Insert mode**:
   - Press `i` to insert before cursor
   - Press `a` to insert after cursor

3. **Type your changes**

4. **Return to Normal mode**:
   - Press `Esc`

## Saving and Quitting

### Saving Files

| Command | Action |
|---------|--------|
| `:w` | Save current file |
| `:w filename.txt` | Save as new file |
| `:wq` | Save and quit |
| `:x` | Save and quit (same as `:wq`) |

**Steps**:
1. Press `Esc` (Normal mode)
2. Type `:w` (you'll see it at the bottom)
3. Press `Enter`

### Quitting

| Command | Action |
|---------|--------|
| `:q` | Quit (only if no changes) |
| `:q!` | Quit without saving (discard changes) |
| `:wq` | Save and quit |
| `ZZ` | Save and quit (shorthand, no colon needed) |
| `ZQ` | Quit without saving (shorthand) |

**Most Common**: `Esc` then `:wq` then `Enter` = save and quit

## Using NixVim Features

### Telescope: Finding Files

Telescope is a powerful file finder (like VS Code's file search).

**Open file finder**:
1. Press `Ctrl+p` (in Normal mode)
2. Start typing filename
3. Use `j`/`k` to navigate results
4. Press `Enter` to open selected file
5. Press `Esc` to cancel

**Live grep (search in files)**:
1. Press `Ctrl+Shift+f` (in Normal mode)
2. Type your search term
3. Results appear as you type
4. Press `Enter` on a result to jump to that file

### Which-Key: Discover Keybindings

Which-Key helps you learn available commands:

1. Press `\` (leader key) in Normal mode
2. A menu appears showing all available commands
3. Press the next key to see more options
4. Press `Esc` to cancel

**Example**: Press `\` then `k` to see Avante-related commands.

### Git Integration (gitsigns)

When editing files in a git repository, you'll see:
- `+` in the gutter = new line
- `~` in the gutter = modified line
- `-` in the gutter = deleted line

Hover over these symbols for commit information.

### LSP Features (Language Intelligence)

When editing code files (`.nix`, `.lua`, `.py`, `.ts`), you get:

**Code Completion**:
- Start typing and suggestions appear
- Use arrow keys to select
- Press `Enter` to accept

**Go to Definition**:
- Move cursor over a symbol
- Press `gd` (go to definition)
- Press `Ctrl+o` to go back

**Hover Information**:
- Move cursor over a symbol
- Press `K` (capital K) to see documentation

**Diagnostics**:
- Errors show with red underlines
- Warnings show with yellow underlines
- Move cursor over them to see details

### Format on Save

Files automatically format when you save:
- `.nix` files → formatted with `nixfmt`
- `.lua` files → formatted with `stylua`

Just save normally (`:w`) and formatting happens automatically!

## Using Avante AI Assistant

Avante is your AI coding assistant (similar to Cursor's Composer). It can help you write code, answer questions, and explain code.

### Prerequisites

**CRITICAL**: Before using Avante, you must set your OpenRouter API key:

1. **Get your OpenRouter API key**:
   - Visit [OpenRouter](https://openrouter.ai/)
   - Sign up/login
   - Go to Keys section
   - Create a new key (starts with `sk-or-v1-...`)

2. **Export the key in your terminal**:
   ```bash
   export OPENAI_API_KEY=sk-or-v1-your-key-here
   ```

3. **Make it permanent** (add to `~/.zshrc` or `~/.bashrc`):
   ```bash
   echo 'export OPENAI_API_KEY=sk-or-v1-your-key-here' >> ~/.zshrc
   source ~/.zshrc
   ```

4. **Restart Neovim** after setting the key

### Opening Avante Chat

1. **Open Neovim** (with a file or empty)
2. **Press `\` then `k`** (leader key + k)
   - Leader key is `\` (backslash) by default
   - You'll see `-- AVANTE --` or a chat panel appear

3. **The chat interface opens**:
   - Usually a side panel or split window
   - Type your question or request
   - Press `Enter` to send

### Using Avante

#### Basic Usage

1. **Ask questions**:
   ```
   How do I write a function in Python?
   ```

2. **Request code changes**:
   ```
   Refactor this function to use async/await
   ```

3. **Get explanations**:
   ```
   Explain what this code does
   ```

4. **Request implementations**:
   ```
   Write a function that sorts a list of dictionaries by a key
   ```

#### Avante Interface

The chat interface typically shows:
- **Input area**: Where you type your questions
- **Response area**: Where Avante's answers appear
- **History**: Previous conversations

**Navigation**:
- Use `Tab` to switch between input and response areas
- Use `Esc` to close Avante chat
- Use `\` then `k` again to toggle Avante on/off

#### Example Workflow

1. **Open a code file**: `nvim mycode.py`
2. **Select code** (optional):
   - Press `v` to enter Visual mode
   - Use arrow keys to select code
   - Press `Esc` to exit Visual mode
3. **Open Avante**: Press `\` then `k`
4. **Ask a question**: "How can I optimize this function?"
5. **Review response**: Read Avante's suggestions
6. **Apply changes**: Copy/paste or manually implement suggestions
7. **Close Avante**: Press `Esc` or `\` then `k` again

### Avante Tips

- **Be specific**: "Add error handling to this function" is better than "fix this"
- **Provide context**: Select relevant code before asking questions
- **Iterate**: Ask follow-up questions to refine solutions
- **Review code**: Always review AI-generated code before using it

## Common Tasks

### Task 1: Create and Edit a New File

1. Open terminal
2. Type `nvim myfile.txt` and press `Enter`
3. Press `i` to enter Insert mode
4. Type your content
5. Press `Esc` to return to Normal mode
6. Type `:w` and press `Enter` to save
7. Type `:q` and press `Enter` to quit

### Task 2: Find and Open a File

1. Open Neovim: `nvim`
2. Press `Ctrl+p` (opens Telescope)
3. Type part of the filename
4. Use `j`/`k` to navigate results
5. Press `Enter` to open

### Task 3: Search for Text Across Files

1. Open Neovim
2. Press `Ctrl+Shift+f` (opens live grep)
3. Type your search term
4. Results appear as you type
5. Press `Enter` on a result to jump to that location

### Task 4: Edit Multiple Lines

1. Move cursor to first line
2. Press `v` to enter Visual mode
3. Use `j` to select multiple lines down
4. Press `d` to delete, or `y` to copy
5. Press `p` to paste

### Task 5: Use Avante to Write Code

1. Open Neovim: `nvim newfile.py`
2. Press `i` to enter Insert mode
3. Type a comment: `# Write a function that calculates factorial`
4. Press `Esc`
5. Press `\` then `k` to open Avante
6. Type: "Write a Python function that calculates factorial"
7. Review Avante's response
8. Copy the code into your file

### Task 6: Get Help Understanding Code

1. Open a code file
2. Move cursor to a function or variable you don't understand
3. Press `\` then `k` to open Avante
4. Type: "Explain what this function does"
5. Avante will explain the code

## Practice Exercises

### Exercise 1: Basic Navigation

1. Open Neovim: `nvim`
2. Press `i` and type a few lines of text
3. Press `Esc`
4. Practice moving:
   - `h`, `j`, `k`, `l` to move
   - `w` to move word by word
   - `gg` to go to top
   - `G` to go to bottom

### Exercise 2: Basic Editing

1. Create a file: `nvim practice.txt`
2. Type some text
3. Practice:
   - `x` to delete characters
   - `dd` to delete lines
   - `yy` to copy a line
   - `p` to paste
   - `u` to undo

### Exercise 3: Using Telescope

1. Open Neovim: `nvim`
2. Press `Ctrl+p`
3. Find a file in your home directory
4. Open it
5. Try `Ctrl+Shift+f` to search for text

### Exercise 4: Using Avante

1. Open Neovim: `nvim test.py`
2. Press `\` then `k` to open Avante
3. Ask: "Write a hello world program in Python"
4. Copy the code into your file
5. Save and test it

## Getting Help

### Built-in Help

**Vim Help**:
- Press `Esc` to Normal mode
- Type `:help` and press `Enter`
- Type `:q` to close help

**Help on Specific Topic**:
- `:help navigation` - Learn about movement
- `:help insert` - Learn about Insert mode
- `:help key-notation` - Understand key notation

### Which-Key Menu

Press `\` (leader) to see available commands. This is the easiest way to discover what you can do.

### Check Plugin Status

Type `:checkhealth` to see status of all plugins and features.

### Common Issues

**"I'm stuck and can't type!"**
- Press `Esc` to return to Normal mode
- You're probably in Normal mode when you want Insert mode

**"I can't quit!"**
- Press `Esc`
- Type `:q!` and press `Enter` (quits without saving)

**"Avante won't open!"**
- Check `OPENAI_API_KEY` is set: `echo $OPENAI_API_KEY`
- Restart Neovim after setting the key
- Ensure you're in Normal mode (press `Esc`) before pressing `\` then `k`

**"Telescope won't open!"**
- Ensure you're in Normal mode (press `Esc`)
- Try `Ctrl+p` again
- Check if you're in a directory with files

## Quick Reference Card

### Essential Commands

```
MOVEMENT:
  h, j, k, l    - Arrow keys (left, down, up, right)
  w, b          - Word forward/backward
  gg, G         - Top/bottom of file

EDITING:
  i             - Enter Insert mode
  Esc           - Return to Normal mode
  x             - Delete character
  dd            - Delete line
  yy            - Copy line
  p             - Paste
  u             - Undo

SAVING/QUITTING:
  :w            - Save
  :q            - Quit
  :wq           - Save and quit
  :q!           - Quit without saving

NIXVIM FEATURES:
  Ctrl+p        - Find files (Telescope)
  Ctrl+Shift+f  - Search files (Telescope)
  \             - Leader key (opens which-key menu)
  \k            - Open Avante AI chat
  gd            - Go to definition
  K             - Show documentation (hover)
```

### Mode Indicators

- `-- INSERT --` = Typing mode (press `Esc` to exit)
- `-- VISUAL --` = Selection mode (press `Esc` to exit)
- No indicator = Normal mode (command mode)

## Next Steps

1. **Practice daily**: Use Neovim for small tasks to build muscle memory
2. **Learn gradually**: Don't try to memorize everything at once
3. **Use Which-Key**: Press `\` to discover commands
4. **Read the full guide**: See [NixVim Module Documentation](./nixvim.md) for advanced features
5. **Explore plugins**: Try different features as you become comfortable

## Related Documentation

- [NixVim Module Documentation](./nixvim.md) - Complete NixVim reference
- [User Modules Guide](README.md) - Overview of all user modules
- [Vim Adventures](https://vim-adventures.com/) - Interactive Vim tutorial (external)
- [OpenRouter Documentation](https://openrouter.ai/docs) - API documentation

## Tips for Learning

1. **Start small**: Learn basic movement and editing first
2. **Use the mouse**: It's okay to use mouse for navigation while learning
3. **Practice regularly**: Even 10 minutes daily helps
4. **Don't give up**: Vim has a learning curve, but it's worth it
5. **Use Avante**: Ask Avante to explain Vim concepts if you're stuck!

Remember: Every Vim expert was once a beginner. Take your time, practice, and don't hesitate to use Avante to help you learn!
