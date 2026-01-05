{ pkgs, ... }:

{
  # LM Studio Module
  # Self-contained module that provides LM Studio configuration and MCP server support
  # Includes Node.js dependency for MCP server execution

  # Install Node.js for MCP server support (provides npm and npx)
  # This makes the module self-contained - no profile-level package additions needed
  home.packages = [ pkgs.nodejs ];

  # Create LM Studio configuration directory
  # Note: LM Studio uses ~/.lmstudio/ (NOT ~/.config/LMStudio/) on Linux
  home.file.".lmstudio/mcp.json".text = ''
    {
      "mcpServers": {
        "brave-search": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-brave-search"],
          "env": {
            "BRAVE_API_KEY": "YOUR_API_KEY_HERE"
          }
        }
      }
    }
  '';

  # Note: The user must manually edit ~/.lmstudio/mcp.json to replace
  # "YOUR_API_KEY_HERE" with their actual Brave Search API key.
  # This is intentional for security - API keys should not be in Nix config
  # (they would be exposed in world-readable /nix/store).
}

