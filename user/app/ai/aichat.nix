{ config, pkgs, userSettings, ... }:

{
  # Aichat Module
  # CLI tool for interacting with LLMs via OpenRouter
  # Creates a template config file that users can copy and modify

  home.packages = [ pkgs.aichat ];
  
  # Create aichat configuration directory and example file
  # We create a template file instead of config.yaml directly to avoid overwriting
  # existing user-configured files (which may contain API keys)
  home.file.".config/aichat/config.yaml.example".text = ''
    # Aichat Configuration for OpenRouter
    # Replace YOUR_OPENROUTER_KEY with your actual OpenRouter API key
    
    model: openai:gpt-4o
    clients:
      - type: openai
        api_key: "YOUR_OPENROUTER_KEY"  # User to replace
        api_base: "https://openrouter.ai/api/v1"
  '';

  # Note: If ~/.config/aichat/config.yaml doesn't exist, copy the example file:
  #   cp ~/.config/aichat/config.yaml.example ~/.config/aichat/config.yaml
  # Then edit ~/.config/aichat/config.yaml to replace "YOUR_OPENROUTER_KEY" with your actual OpenRouter API key.
  # This approach prevents Home Manager from overwriting existing configuration files.
  # Security: API keys should not be in Nix config (they would be exposed in world-readable /nix/store).
}

