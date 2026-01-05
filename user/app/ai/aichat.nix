{ config, pkgs, userSettings, ... }:

{
  home.packages = [ pkgs.aichat ];
  
  home.file.".config/aichat/config.yaml".text = ''
    # Aichat Configuration for OpenRouter
    # Replace YOUR_OPENROUTER_KEY with your actual OpenRouter API key
    
    model: openai:gpt-4o
    clients:
      - type: openai
        api_key: "YOUR_OPENROUTER_KEY"  # User to replace
        api_base: "https://openrouter.ai/api/v1"
  '';
}

