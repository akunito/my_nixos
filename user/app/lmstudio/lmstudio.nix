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
  # We create a template file instead of mcp.json directly to avoid overwriting
  # existing user-configured files (which may contain API keys)
  home.file.".lmstudio/mcp.json.example".text = ''
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

  # Note: If ~/.lmstudio/mcp.json doesn't exist, copy the example file:
  #   cp ~/.lmstudio/mcp.json.example ~/.lmstudio/mcp.json
  # Then edit ~/.lmstudio/mcp.json to replace "YOUR_API_KEY_HERE" with your actual Brave Search API key.
  # This approach prevents Home Manager from overwriting existing configuration files.
  # Security: API keys should not be in Nix config (they would be exposed in world-readable /nix/store).
}

