---
id: user-modules.lmstudio
summary: LM Studio user module, including MCP server setup templates and web-search tooling integration guidance.
tags: [lmstudio, mcp, ai, user-modules]
related_files:
  - user/app/lmstudio/**
  - docs/user-modules/lmstudio.md
key_files:
  - user/app/lmstudio/lmstudio.nix
  - docs/user-modules/lmstudio.md
activation_hints:
  - If configuring LM Studio, MCP servers, or related user-level setup
---

# LM Studio Module

Complete guide for the LM Studio user module, including web search capabilities, plugin installation, and browser extensions.

## Table of Contents

- [Overview](#overview)
- [Module Features](#module-features)
- [Installation](#installation)
- [MCP Server Setup](#mcp-server-setup)
- [Manual Optimization](#manual-optimization)
- [Plugin Installation](#plugin-installation)
- [Browser Extensions](#browser-extensions)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

## Overview

The LM Studio module provides a self-contained configuration for LM Studio, including:

- LM Studio application (installed via systemPackages in profile config)
- Node.js dependency for MCP server support (included in module)
- MCP server template configuration for web search capabilities
- Documentation for plugins and browser extensions

**Module Location**: `user/app/lmstudio/lmstudio.nix`

## Module Features

- **Self-contained**: Includes Node.js dependency directly (no profile config changes needed)
- **MCP Server Template**: Creates `~/.lmstudio/mcp.json.example` template file (won't overwrite existing `mcp.json`)
- **Security-focused**: Does not hardcode API keys (user must add manually) and protects existing configuration

## Installation

The module is automatically available when imported in your profile's `home.nix`:

```nix
imports = [
  # ... other imports ...
  ../../user/app/lmstudio/lmstudio.nix
];
```

**Note**: LM Studio must be installed in `systemPackages` in your profile configuration (e.g., `profiles/DESK-config.nix`). The module handles user-level configuration only.

## MCP Server Setup

### What is MCP?

Model Context Protocol (MCP) allows LM Studio models to interact with external tools and services, such as web search APIs.

### Brave Search MCP Server

The module creates a template configuration file at `~/.lmstudio/mcp.json.example` with a placeholder for the Brave Search API key. This prevents overwriting existing `mcp.json` files that may already contain your API key.

#### Step 1: Obtain Brave Search API Key

1. Visit [Brave Search API](https://brave.com/search/api/)
2. Sign up for a free account
3. Get your API key (free tier: 2,000 queries/month)

#### Step 2: Create Configuration File

The module creates a template file at `~/.lmstudio/mcp.json.example`. 

**If `~/.lmstudio/mcp.json` doesn't exist:**
1. Copy the example file:
   ```sh
   cp ~/.lmstudio/mcp.json.example ~/.lmstudio/mcp.json
   ```

**If `~/.lmstudio/mcp.json` already exists:**
- The module won't overwrite it (to protect your API key)
- You can use the example file as a reference if needed

#### Step 3: Configure API Key

1. Open `~/.lmstudio/mcp.json` in your editor
2. Replace `"YOUR_API_KEY_HERE"` with your actual Brave Search API key:

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "your_actual_api_key_here"
      }
    }
  }
}
```

3. Save the file

#### Step 4: Enable MCP Server in LM Studio

1. Open LM Studio
2. Navigate to **Settings** → **Integrations** (or **MCP Servers**)
3. Find "brave-search" in the list
4. Enable it
5. Restart LM Studio if prompted

#### Step 5: Verify Setup

1. Start a chat in LM Studio
2. Ask the model to search the web for something
3. The model should be able to perform web searches using Brave Search

**Reference**: [Add MCP servers in LM Studio—step-by-step video guide](https://www.youtube.com/watch?v=gRJJP3zqUdA)

### Important Notes

- **Configuration Path**: LM Studio uses `~/.lmstudio/mcp.json` on Linux (NOT `~/.config/LMStudio/mcp.json`)
- **API Key Security**: Never commit your API key to git or include it in Nix configuration files
- **Node.js Required**: The module includes Node.js, but ensure `npx` is accessible in your PATH

## Manual Optimization

**IMPORTANT**: The following settings CANNOT be configured via Nix/Home Manager. They must be set manually in the LM Studio GUI because LM Studio stores these settings in internal databases (LevelDB/SQLite), not in editable config files.

### Context Length

1. Open LM Studio
2. Go to **My Models** tab
3. Click the gear icon next to your model
4. Set **Context Length** (recommended: 8192 tokens for most use cases)
5. Save settings

### GPU Offload

For AMD GPU users:

1. When loading a model, adjust the **GPU Offload** slider
2. Higher values use more GPU memory but provide faster inference
3. Recommended: Start with 50% and adjust based on your GPU memory

### Flash Attention

1. In model settings, enable **Flash Attention** if available
2. This can improve performance and reduce memory usage
3. Not all models support Flash Attention

### Model Presets

1. Create presets for different use cases:
   - Go to **Presets** section
   - Create new preset with system prompt and parameters
   - Save for reuse across chats

2. Common presets:
   - **Code Assistant**: Optimized for programming tasks
   - **General Chat**: Balanced for conversations
   - **Research**: Optimized for information gathering

### System Prompt Templates

1. Configure system prompts in the **Presets** section
2. Create templates for different roles (assistant, code reviewer, researcher, etc.)
3. Save and reuse across sessions

## Plugin Installation

LM Studio supports plugins installed via the LM Studio Hub. These are installed manually through the application UI.

### DuckDuckGo Search Plugin

**Purpose**: Provides web and image search capabilities using DuckDuckGo.

**Installation**:
1. Open LM Studio
2. Navigate to **Plugins** or **Hub** section
3. Search for "DuckDuckGo Search Tool"
4. Click **Install**
5. Configure plugin settings:
   - **Search Results Per Page**: Set number of results (default: 10)
   - **Safe Search**: Enable/disable safe search filtering

**Usage**:
- Ask the model to "search the web for [query]"
- Ask the model to "show images of [query]"
- The plugin will perform searches and display results

**Plugin Page**: Available in LM Studio Hub

### Visit Website Plugin

**Purpose**: Allows the assistant to visit web pages and extract content from URLs.

**Installation**:
1. Open LM Studio
2. Navigate to **Plugins** or **Hub** section
3. Search for "Visit Website"
4. Click **Install**

**Usage**:
- Ask the model to "visit [URL]" or "read [URL]"
- The plugin will fetch the webpage content
- Particularly useful when combined with search tools to analyze specific pages

**Plugin Page**: Available in LM Studio Hub

### Recommended Plugin Combinations

- **DuckDuckGo + Visit Website**: Search for information, then visit relevant URLs
- **DuckDuckGo + Brave Search MCP**: Multiple search sources for comprehensive results

## Browser Extensions

### LLM Face Extension

**Purpose**: Integrate local LLMs with your browser for private AI processing.

**Features**:
- Interact with LM Studio models directly from browser
- Text analysis, summarization, translation
- All processing happens locally (privacy-focused)
- Custom prompts and workflows

**Installation** (Vivaldi/Chrome/Chromium):
1. Visit [Chrome Web Store - LLM Face](https://chromewebstore.google.com/detail/llm-face/emecemjplacegbfnmobpnggdeaeiklbb)
2. Click **Add to Chrome** (works in Vivaldi)
3. Extension will be added to your browser

**Configuration**:
1. Click the extension icon
2. Configure connection to local LM Studio instance
3. Default connection: `http://localhost:1234` (LM Studio's default API port)
4. Test connection to ensure it works

**Usage**:
- Select text on any webpage
- Right-click → **LLM Face** → Choose action (summarize, translate, etc.)
- Or use the extension popup for custom prompts

### LM Studio Assistant Extension

**Purpose**: Text analysis, code review, and translation directly in the browser.

**Features**:
- Text analysis and processing
- Code review capabilities
- Translation between languages
- All processing happens locally via LM Studio

**Installation** (Vivaldi/Chrome/Chromium):
1. Visit [Chrome Web Store - LM Studio Assistant](https://chromewebstore.google.com/detail/lm-studio-assistant/iefmcbandkegenedffmjefjjnccohnke)
2. Click **Add to Chrome** (works in Vivaldi)
3. Extension will be added to your browser

**Configuration**:
1. Open extension settings
2. Configure API endpoint (default: `http://localhost:1234`)
3. Select default model if available
4. Test connection

**Usage**:
- Select text and use extension context menu
- Or use extension popup for direct interaction
- Code review: Paste code and ask for review
- Translation: Select text and translate

### Browser Extension Setup Tips

1. **Enable LM Studio Local Server**:
   - Open LM Studio
   - Go to **Settings** → **Server**
   - Enable **Local Server**
   - Note the port (default: 1234)

2. **Firewall Configuration**:
   - Ensure localhost connections are allowed
   - No external firewall rules needed (local only)

3. **Model Selection**:
   - Load a model in LM Studio before using extensions
   - Extensions will use the currently loaded model

4. **Performance**:
   - Larger models provide better results but slower responses
   - Consider model size vs. response time for your use case

## Troubleshooting

### MCP Server Not Working

**Problem**: Brave Search MCP server doesn't appear in LM Studio.

**Solutions**:
1. Verify `~/.lmstudio/mcp.json` exists and is valid JSON
2. Check that API key is correctly set (not the placeholder)
3. Ensure Node.js is installed: `which npx` should return a path
4. Test MCP server manually: `npx -y @modelcontextprotocol/server-brave-search`
5. Check LM Studio logs for errors
6. Restart LM Studio after configuration changes

### Node.js Not Found

**Problem**: `npx` command not found when MCP server tries to run.

**Solutions**:
1. Verify Node.js is installed: `node --version`
2. Check PATH includes Node.js: `echo $PATH | grep node`
3. Restart your shell/terminal after Home Manager rebuild
4. Verify module is imported in `home.nix`

### API Key Issues

**Problem**: MCP server fails with authentication errors.

**Solutions**:
1. Verify API key is correct (no extra spaces or quotes)
2. Check API key hasn't expired
3. Verify API key quota hasn't been exceeded (free tier: 2,000/month)
4. Test API key directly: Visit Brave Search API documentation

### Browser Extensions Can't Connect

**Problem**: Extensions can't connect to LM Studio.

**Solutions**:
1. Ensure LM Studio local server is running
2. Check server port (default: 1234)
3. Verify no firewall blocking localhost
4. Test API endpoint: `curl http://localhost:1234/v1/models`
5. Check LM Studio server settings for CORS/access restrictions

### Configuration File Not Found

**Problem**: `~/.lmstudio/mcp.json` doesn't exist.

**Solutions**:
1. Copy the example file: `cp ~/.lmstudio/mcp.json.example ~/.lmstudio/mcp.json`
2. Edit the file to add your API key (see MCP Server Setup section)
3. Rebuild Home Manager: `home-manager switch`
4. Check Home Manager logs for errors
5. Manually create directory: `mkdir -p ~/.lmstudio`
6. Verify module is imported in profile's `home.nix`

### Home Manager Clobber Warning

**Problem**: Home Manager warns about overwriting `~/.lmstudio/mcp.json`.

**Cause**: The file already exists (likely with your API key configured).

**Solution**: The module now creates `mcp.json.example` instead of `mcp.json` to avoid this issue. Your existing `mcp.json` file will not be overwritten.

### Model Performance Issues

**Problem**: Slow inference or high memory usage.

**Solutions**:
1. Adjust GPU offload ratio (see Manual Optimization section)
2. Reduce context length if not needed
3. Use smaller models for faster responses
4. Enable Flash Attention if supported
5. Close other GPU-intensive applications

## Security Considerations

### API Key Management

**CRITICAL**: Never commit API keys to git or include them in Nix configuration files.

**Why**: API keys in Nix expressions are stored in the world-readable `/nix/store`, making them accessible to any user on the system.

**Best Practices**:
1. **Manual Configuration**: Edit `~/.lmstudio/mcp.json` manually (current approach)
2. **Environment Variables**: Store API key in `~/.config/secrets/` and reference via env var
3. **Secret Management**: Consider using `sops-nix` or similar for advanced secret management
4. **Git Ignore**: Add `~/.lmstudio/mcp.json` to `.gitignore` if version controlling dotfiles

### Local Processing

**Advantage**: LM Studio processes everything locally, so:
- No data sent to external servers
- Privacy-focused AI interactions
- Works offline (after model download)

**Considerations**:
- Models can be large (several GB)
- GPU memory requirements for optimal performance
- Local processing means your hardware handles all computation

### Network Access

**MCP Servers**: Require network access to function (web search, etc.)

**Browser Extensions**: Only connect to localhost (no external network access needed)

**Firewall**: No special firewall rules needed for local-only usage

## Related Documentation

- [User Modules Guide](../user-modules.md) - Overview of all user modules
- [Configuration Guide](../configuration.md) - Understanding configuration structure
- [LM Studio Documentation](https://lmstudio.ai/docs) - Official LM Studio documentation

## Module Configuration Reference

The module creates the following:

- **Directory**: `~/.lmstudio/`
- **Template File**: `~/.lmstudio/mcp.json.example` (template with placeholder - copy to `mcp.json` if needed)
- **Packages**: `nodejs` (includes npm and npx)

**Note**: The module creates `mcp.json.example` instead of `mcp.json` to avoid overwriting existing configuration files that may contain your API key.

**Module File**: `user/app/lmstudio/lmstudio.nix`

**Import Path**: `../../user/app/lmstudio/lmstudio.nix` (from profile `home.nix`)

