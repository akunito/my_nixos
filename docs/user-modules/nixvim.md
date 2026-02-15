---
id: user-modules.nixvim
summary: NixVim configuration module providing a Cursor IDE-like Neovim experience with AI-powered features (Avante + Supermaven), LSP intelligence, and modern editor UX.
tags: [nixvim, neovim, editor, ai, lsp, cursor-ide, user-modules]
related_files:
  - user/app/nixvim/**
  - docs/user-modules/nixvim.md
key_files:
  - user/app/nixvim/nixvim.nix
  - docs/user-modules/nixvim.md
activation_hints:
  - If configuring Neovim, AI coding assistants, or LSP servers
  - If enabling NixVim for DESK or LAPTOP profiles
---

# NixVim Module

Complete guide for the NixVim configuration module, providing a Cursor IDE-like experience with AI-powered coding assistance, LSP intelligence, and modern editor features.

## Table of Contents

- [Overview](#overview)
- [What is NixVim?](#what-is-nixvim)
- [Features](#features)
- [Installation & Configuration](#installation--configuration)
- [AI Features](#ai-features)
- [Core Intelligence](#core-intelligence)
- [UI & UX](#ui--ux)
- [Keybindings](#keybindings)
- [Configuration Reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Overview

The NixVim module provides a reproducible, declarative Neovim configuration that replicates the Cursor IDE experience. It includes:

- **AI "Composer" Agent** (Avante) - Chat-based AI coding assistant via OpenRouter
- **AI Autocomplete** (Supermaven) - Intelligent code completion
- **LSP Servers** - Language support for Nix, Lua, Python, and TypeScript
- **Treesitter** - Syntax highlighting and code parsing
- **Formatting** - Automatic format-on-save for Nix and Lua
- **Modern UI** - Telescope, gitsigns, which-key, and web-devicons

**Module Location**: `user/app/nixvim/nixvim.nix`

## What is NixVim?

[NixVim](https://github.com/nix-community/nixvim) is a Neovim distribution configured and distributed through Nix. It allows you to:

- **Declarative Configuration**: Define your entire Neovim setup in Nix, making it reproducible and version-controlled
- **Module System**: Use Nix modules to configure plugins, LSP servers, keybindings, and more
- **Reproducibility**: Same configuration works across different machines and environments
- **Integration**: Seamlessly integrates with NixOS and Home Manager

Unlike traditional Neovim configurations (using `init.lua` or `init.vim`), NixVim configurations are:

- **Type-safe**: Nix's type system catches configuration errors at build time
- **Composable**: Mix and match modules from the NixVim ecosystem
- **Testable**: Can be validated before deployment
- **Shareable**: Easy to share and reuse configurations

## Features

### AI-Powered Coding

- **Avante**: Chat-based AI assistant (similar to Cursor's Composer)
  - Configured for OpenRouter API (supports multiple AI models)
  - Toggle with `<Leader>k`
  - Uses OpenAI-compatible API structure

- **Supermaven**: Intelligent autocomplete
  - Tab to accept suggestions
  - Context-aware code completion
  - Fast, local-first autocomplete

### Language Intelligence

- **LSP Servers**: Full language support for:
  - `nixd` - Nix language server
  - `lua_ls` - Lua language server
  - `pyright` - Python language server
  - `ts_ls` - TypeScript/JavaScript language server

- **Treesitter**: Advanced syntax highlighting and code parsing

- **Formatting**: Automatic format-on-save
  - Nix files: `nixfmt`
  - Lua files: `stylua`

### Modern Editor UX

- **Telescope**: Powerful fuzzy finder for files, grep, and more
- **Git Integration**: `gitsigns` for inline git status
- **Which-Key**: Interactive keybinding discovery
- **Web Devicons**: File type icons in file explorer

## Installation & Configuration

### Profile-Based Enablement

NixVim is controlled via the `nixvimEnabled` variable in profile configurations:

**Default**: Disabled for all profiles (`nixvimEnabled = false` in `lib/defaults.nix`)

**Enabled Profiles**:
- **DESK**: `nixvimEnabled = true` in `profiles/DESK-config.nix`
- **LAPTOP**: `nixvimEnabled = true` in `profiles/LAPTOP-config.nix`

### Module Import

The module is automatically imported in `profiles/work/home.nix` when `nixvimEnabled = true`:

```nix
++ lib.optional systemSettings.nixvimEnabled ../../user/app/nixvim/nixvim.nix
```

### Enabling for Other Profiles

To enable NixVim for additional profiles:

1. **Add to profile config** (e.g., `profiles/YOURPROFILE-config.nix`):
   ```nix
   systemSettings = {
     # ... other settings ...
     nixvimEnabled = true;
   };
   ```

2. **Rebuild**: The module will be automatically imported on the next rebuild

### Flake Input

NixVim is added as a flake input in `flake.nix`:

```nix
nixvim = {
  url = "github:nix-community/nixvim";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**Note**: If enabling for other profiles, add the same input to their respective flake files.

## AI Features

### Avante (AI Composer)

Avante provides chat-based AI coding assistance, similar to Cursor's Composer feature.

#### Configuration

The module is pre-configured to use OpenRouter API:

```nix
plugins.avante = {
  enable = true;
  settings = {
    provider = "openai";
    openai = {
      endpoint = "https://openrouter.ai/api/v1";
      model = "anthropic/claude-3.5-sonnet";
      temperature = 0;
      max_tokens = 4096;
    };
  };
};
```

#### Setup

**CRITICAL**: You must export your OpenRouter API key before using Avante:

```bash
export OPENAI_API_KEY=sk-or-v1-...
```

Add this to your shell configuration (e.g., `~/.zshrc` or `~/.bashrc`) to make it persistent:

```bash
# OpenRouter API key for NixVim Avante
export OPENAI_API_KEY=sk-or-v1-...
```

**Security Note**: Never commit API keys to git or include them in Nix configuration files. They would be stored in the world-readable `/nix/store`.

#### Usage

- **Toggle Chat**: Press `<Leader>k` (default leader is `\`)
- **Chat Interface**: Opens a side panel for AI conversations
- **Code Assistance**: Ask questions, request code changes, get explanations

#### Model Selection

The default model is `anthropic/claude-3.5-sonnet` via OpenRouter. To use a different model:

1. Edit `user/app/nixvim/nixvim.nix`
2. Change the `model` field to your desired OpenRouter model ID
3. Rebuild: `./install.sh ~/.dotfiles DESK -s`

**Popular OpenRouter Models**:
- `anthropic/claude-3.5-sonnet` - Current default (high quality)
- `openai/gpt-4o` - OpenAI GPT-4
- `google/gemini-pro-1.5` - Google Gemini
- `meta-llama/llama-3.1-70b-instruct` - Meta Llama

### Supermaven (AI Autocomplete)

Supermaven provides intelligent, context-aware code completion.

#### Configuration

Supermaven is configured via `extraConfigLua`:

```lua
require("supermaven-nvim").setup({
  keymaps = {
    accept_suggestion = "<Tab>",
    clear_suggestion = "<C-]>",
    accept_word = "<C-j>",
  },
})
```

#### Keybindings

- **`<Tab>`**: Accept the full suggestion
- **`<C-]>`**: Clear/dismiss the current suggestion
- **`<C-j>`**: Accept only the next word of the suggestion

#### Usage

Supermaven works automatically as you type. It analyzes your code context and provides intelligent completions inline.

## Core Intelligence

### LSP Servers

Language Server Protocol (LSP) provides intelligent code features:

- **Code Completion**: Context-aware suggestions
- **Go to Definition**: Jump to symbol definitions
- **Find References**: Find all usages of a symbol
- **Hover Information**: Documentation on hover
- **Diagnostics**: Real-time error and warning detection
- **Code Actions**: Quick fixes and refactorings

#### Configured Servers

- **nixd**: Nix language server
  - Provides completion, diagnostics, and formatting for `.nix` files
  - Integrated with NixOS and Home Manager configurations

- **lua_ls**: Lua language server
  - Full Lua language support
  - Works with Neovim configuration files

- **pyright**: Python language server
  - Type checking, completion, and diagnostics
  - Fast and accurate Python support

- **ts_ls**: TypeScript/JavaScript language server
  - Full TypeScript and JavaScript support
  - Works with modern web development

#### Adding More LSP Servers

To add additional LSP servers, edit `user/app/nixvim/nixvim.nix`:

```nix
plugins.lsp = {
  enable = true;
  servers = {
    nixd.enable = true;
    lua_ls.enable = true;
    pyright.enable = true;
    ts_ls.enable = true;
    # Add more servers:
    rust_analyzer.enable = true;
    gopls.enable = true;
  };
};
```

### Treesitter

Treesitter provides advanced syntax highlighting and code parsing:

- **Syntax Highlighting**: More accurate than regex-based highlighting
- **Code Folding**: Intelligent code folding based on syntax tree
- **Incremental Parsing**: Fast, efficient parsing
- **Multiple Languages**: Supports many languages out of the box

#### Configuration

Treesitter is enabled with highlighting:

```nix
plugins.treesitter = {
  enable = true;
  highlight.enable = true;
};
```

### Formatting

Automatic format-on-save is configured for Nix and Lua files:

- **Nix**: Uses `nixfmt` formatter
- **Lua**: Uses `stylua` formatter

#### Configuration

```nix
plugins.conform-nvim = {
  enable = true;
  formatOnSave = {
    lspFallback = true;
    timeoutMs = 500;
  };
  formattersByFt = {
    nix = [ "nixfmt" ];
    lua = [ "stylua" ];
  };
};
```

#### Adding More Formatters

To add formatters for additional languages:

```nix
formattersByFt = {
  nix = [ "nixfmt" ];
  lua = [ "stylua" ];
  python = [ "black" ];  # Example: Python formatter
  javascript = [ "prettier" ];  # Example: JS formatter
};
```

**Note**: Ensure the formatter packages are available in your environment or add them to `home.packages`.

## UI & UX

### Telescope

Telescope is a powerful fuzzy finder for Neovim:

- **File Finding**: Quickly locate and open files
- **Live Grep**: Search across files with live results
- **Buffers**: Switch between open buffers
- **Git Integration**: Browse git files, commits, branches

**Keybindings**:
- `<C-p>`: Find files
- `<C-S-f>`: Live grep (search across files)

### Git Integration

**gitsigns** provides inline git status:

- Shows added/modified/deleted lines in the gutter
- Hover for commit information
- Blame information on demand

### Which-Key

Which-Key provides interactive keybinding discovery:

- Press a prefix key to see all available commands
- Learn keybindings interactively
- No need to memorize all key combinations

### Web Devicons

File type icons in the file explorer and throughout the UI:

- Visual file type identification
- Better visual hierarchy
- Improved navigation experience

## Keybindings

### Cursor-Like Mappings

The configuration includes keybindings inspired by Cursor IDE:

| Keybinding | Action | Description |
|------------|--------|-------------|
| `<Leader>k` | `:AvanteToggle<CR>` | Toggle Avante AI chat |
| `<C-p>` | `:Telescope find_files<CR>` | Find files |
| `<C-S-f>` | `:Telescope live_grep<CR>` | Live grep (search files) |

**Note**: Default leader key is `\` (backslash). Press `\` then `k` to open Avante.

### Customizing Keybindings

To add or modify keybindings, edit `user/app/nixvim/nixvim.nix`:

```nix
keymaps = [
  {
    mode = "n";  # Normal mode
    key = "<leader>k";
    action = ":AvanteToggle<CR>";
    options = {
      desc = "Toggle Avante chat";
      silent = true;
    };
  }
  # Add more keymaps here...
];
```

**Modes**:
- `"n"`: Normal mode
- `"i"`: Insert mode
- `"v"`: Visual mode
- `"x"`: Visual block mode

## Configuration Reference

### Module Structure

The NixVim module is located at `user/app/nixvim/nixvim.nix` and includes:

```nix
{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    # ... plugin and configuration options ...
  };
}
```

### Key Configuration Sections

1. **AI Features**: Avante and Supermaven configuration
2. **LSP**: Language server configuration
3. **Treesitter**: Syntax highlighting
4. **Formatting**: Conform-nvim with format-on-save
5. **UI Plugins**: Telescope, gitsigns, which-key, web-devicons
6. **Keymaps**: Custom keybindings
7. **Options**: Neovim options (number, relativenumber, clipboard, etc.)
8. **Plugin Loading Safety**: Safe require wrapper in `extraConfigLuaPre` to handle plugin loading timing issues

### Neovim Options

Neovim options are set via `extraConfigLua`:

```lua
vim.opt.number = true          -- Line numbers
vim.opt.relativenumber = true  -- Relative line numbers
vim.opt.shiftwidth = 2         -- Indent width
vim.opt.tabstop = 2            -- Tab width
vim.opt.expandtab = true       -- Use spaces instead of tabs
vim.opt.clipboard = "unnamedplus"  -- System clipboard integration
```

### Clipboard Integration

The configuration includes Wayland clipboard support:

- Uses `wl-copy` and `wl-paste` on Wayland systems
- Configured via `vim.opt.clipboard = "unnamedplus"`
- Works automatically with `wl-clipboard` package (typically pre-installed on Wayland)

## Troubleshooting

### Avante Not Working

**Problem**: Avante chat doesn't open or shows API errors.

**Solutions**:
1. **Check API Key**: Ensure `OPENAI_API_KEY` is exported:
   ```bash
   echo $OPENAI_API_KEY
   ```
   Should show your OpenRouter key starting with `sk-or-v1-...`

2. **Export in Shell**: Add to `~/.zshrc` or `~/.bashrc`:
   ```bash
   export OPENAI_API_KEY=sk-or-v1-...
   ```

3. **Restart Terminal**: After adding to shell config, restart your terminal

4. **Verify OpenRouter**: Test your API key at [OpenRouter Dashboard](https://openrouter.ai/keys)

5. **Check Model**: Ensure the model ID is correct (e.g., `anthropic/claude-3.5-sonnet`)

### Supermaven Not Working

**Problem**: No autocomplete suggestions appear.

**Solutions**:
1. **Check Plugin**: Verify Supermaven is loaded:
   ```vim
   :checkhealth supermaven
   ```

2. **Keybindings**: Try the keybindings:
   - `<Tab>` to accept
   - `<C-]>` to clear

3. **Restart Neovim**: Sometimes plugins need a restart after installation

### LSP Servers Not Starting

**Problem**: LSP features (completion, diagnostics) don't work.

**Solutions**:
1. **Check LSP Status**: 
   ```vim
   :LspInfo
   ```
   Shows which servers are running

2. **Install Language Tools**: Ensure language tools are available:
   - `nixd` for Nix
   - `lua-language-server` for Lua
   - `pyright` for Python
   - `typescript-language-server` for TypeScript

3. **Check File Type**: Ensure file type is detected:
   ```vim
   :set filetype?
   ```

4. **LSP Logs**: Check LSP logs for errors:
   ```vim
   :LspLog
   ```

### Format-on-Save Not Working

**Problem**: Files don't format automatically on save.

**Solutions**:
1. **Check Formatters**: Ensure formatters are installed:
   - `nixfmt` for Nix files
   - `stylua` for Lua files

2. **Verify File Type**: Format-on-save only works for configured file types (currently Nix and Lua)

3. **Check Conform**: Verify conform-nvim is enabled:
   ```vim
   :checkhealth conform
   ```

4. **Manual Format**: Try manual formatting:
   ```vim
   :Format
   ```

### Clipboard Not Working

**Problem**: Copy/paste doesn't work with system clipboard.

**Solutions**:
1. **Check Wayland**: Ensure you're on Wayland (SwayFX):
   ```bash
   echo $WAYLAND_DISPLAY
   ```

2. **Install wl-clipboard**: 
   ```bash
   nix-shell -p wl-clipboard
   ```

3. **Test Clipboard**: Test `wl-copy` and `wl-paste`:
   ```bash
   echo "test" | wl-copy
   wl-paste
   ```

4. **Check Neovim**: In Neovim, test:
   ```vim
   :set clipboard?
   ```
   Should show `clipboard=unnamedplus`

### Build Errors

**Problem**: Home Manager build fails with NixVim errors.

**Solutions**:
1. **Update Flake**: Ensure nixvim input is up to date:
   ```bash
   nix flake update nixvim
   ```

2. **Check Syntax**: Verify `nixvim.nix` syntax is correct

3. **Check Imports**: Ensure `inputs.nixvim.homeModules.nixvim` is correct (not `homeManagerModules`)

4. **Rebuild**: Try rebuilding:
   ```bash
   ./install.sh ~/.dotfiles DESK -s
   ```

### Plugin Loading Errors

**Problem**: Errors like `module 'nvim-web-devicons' not found` or `module 'which-key' not found` when starting Neovim.

**Cause**: NixVim generates `require()` calls in `init.lua` before plugins are fully loaded into the runtime path. This is a timing issue where the generated configuration tries to require plugins that haven't been added to Neovim's runtime path yet.

**Solution**: The configuration includes a safe require wrapper in `extraConfigLuaPre` that:
- Intercepts `require()` calls for plugins that might not be loaded yet
- Uses `pcall()` to safely attempt loading
- Returns dummy modules if plugins aren't available (prevents errors)
- Allows plugins to load properly once they're in the runtime path

**Plugins Handled**:
- `nvim-web-devicons` (required by Telescope)
- `which-key` (keybinding discovery)
- `telescope`, `gitsigns`, `dressing`, `conform` (UI plugins)
- `avante`, `avante_lib` (AI assistant)
- `supermaven-nvim` (AI autocomplete)

**Verification**: Test if plugins are available:
```vim
:lua print(pcall(require, 'nvim-web-devicons'))
:lua print(pcall(require, 'which-key'))
```

**Note**: This is a workaround for a known NixVim timing issue. The configuration uses official NixVim plugin modules (`plugins.web-devicons.enable = true`, etc.) but adds the safe require wrapper to handle the loading order.

## Security Considerations

### API Keys

**CRITICAL**: Never commit API keys to git or include them in Nix configuration files.

**Why**: Nix stores all derivations in `/nix/store`, which is world-readable. Any API keys in Nix files would be accessible to all users on the system.

**Best Practices**:
1. **Environment Variables**: Store API keys in environment variables (current approach)
2. **Shell Configuration**: Add to `~/.zshrc` or `~/.bashrc` (not version controlled)
3. **Secret Management**: For advanced setups, consider `sops-nix` or similar
4. **Git Ignore**: If version controlling shell configs, ensure API keys are in separate, ignored files

### OpenRouter API Keys

- **Format**: OpenRouter keys start with `sk-or-v1-...`
- **Storage**: Store in environment variable `OPENAI_API_KEY`
- **Scope**: Keys have access to all models available on OpenRouter
- **Quota**: Check your OpenRouter dashboard for usage and limits

### Local Processing

- **Supermaven**: Processes code locally (no external API calls)
- **LSP Servers**: Run locally on your machine
- **Treesitter**: Local syntax parsing
- **Avante**: Requires internet connection for AI API calls

## Related Documentation

- [User Modules Guide](README.md) - Overview of all user modules
- [Configuration Guide](../configuration.md) - Understanding configuration structure
- [NixVim Documentation](https://nix-community.github.io/nixvim/) - Official NixVim documentation
- [Neovim Documentation](https://neovim.io/doc/) - Official Neovim documentation

## Module Configuration Reference

The module is located at:

- **Module File**: `user/app/nixvim/nixvim.nix`
- **Import Path**: `../../user/app/nixvim/nixvim.nix` (from `profiles/work/home.nix`)
- **Flake Input**: `inputs.nixvim` in `flake.nix`

### Dependencies

The module automatically includes:

- **Formatters**: `nixfmt`, `stylua` (via `home.packages`)
- **LSP Servers**: Configured via NixVim plugin system
- **Plugins**: All plugins managed via NixVim

### Profile Integration

- **Variable**: `systemSettings.nixvimEnabled`
- **Default**: `false` (in `lib/defaults.nix`)
- **Enabled For**: DESK and LAPTOP profiles
- **Import Location**: `profiles/work/home.nix`
