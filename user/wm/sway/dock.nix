{ config, pkgs, lib, systemSettings, ... }:

{
  # nwg-dock configuration (Sway-compatible Python version)
  # The dock is started via exec-once in default.nix
  # This file provides the CSS styling for the dock
  
  # Create grid.svg for nwg-dock launcher button
  home.file.".local/share/nwg-dock/images/grid.svg".text = ''
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <rect x="3" y="3" width="7" height="7"/>
      <rect x="14" y="3" width="7" height="7"/>
      <rect x="3" y="14" width="7" height="7"/>
      <rect x="14" y="14" width="7" height="7"/>
    </svg>
  '';
  
  home.file.".config/nwg-dock/style.css".text = if systemSettings.stylixEnable == true then ''
    /* nwg-dock Frosted Glass styling with Stylix colors */
    
    window {
      background-color: rgba(${config.lib.stylix.colors.base00}, 0.6);
      border-radius: 20px;
      border: 1px solid rgba(${config.lib.stylix.colors.base02}, 0.3);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
    }
    
    #dock {
      padding: 8px;
      spacing: 8px;
    }
    
    #dock button {
      background-color: rgba(${config.lib.stylix.colors.base01}, 0.5);
      border-radius: 12px;
      padding: 8px;
      border: 1px solid rgba(${config.lib.stylix.colors.base02}, 0.2);
      transition: all 0.2s ease;
    }
    
    #dock button:hover {
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.3);
      transform: scale(1.1);
    }
    
    #dock button:active {
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.5);
    }
    
    #dock button.running {
      border: 2px solid #${config.lib.stylix.colors.base0D};
    }
    
    #dock button.focused {
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.4);
      border: 2px solid #${config.lib.stylix.colors.base0D};
    }
  '' else ''
    /* nwg-dock Frosted Glass styling (fallback) */
    
    window {
      background-color: rgba(0, 0, 0, 0.6);
      border-radius: 20px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      backdrop-filter: blur(10px);
      -webkit-backdrop-filter: blur(10px);
    }
    
    #dock {
      padding: 8px;
      spacing: 8px;
    }
    
    #dock button {
      background-color: rgba(255, 255, 255, 0.1);
      border-radius: 12px;
      padding: 8px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      transition: all 0.2s ease;
    }
    
    #dock button:hover {
      background-color: rgba(255, 255, 255, 0.2);
      transform: scale(1.1);
    }
    
    #dock button.running {
      border: 2px solid #4a9eff;
    }
    
    #dock button.focused {
      background-color: rgba(74, 158, 255, 0.3);
      border: 2px solid #4a9eff;
    }
  '';
}

