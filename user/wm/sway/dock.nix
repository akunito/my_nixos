{ config, pkgs, lib, systemSettings, userSettings, ... }:

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
  
  # CRITICAL: Check if Stylix is actually available (not just enabled)
  # Stylix is disabled for Plasma 6 even if stylixEnable is true
  home.file.".config/nwg-dock/style.css".text = if (systemSettings.stylixEnable == true && userSettings.wm != "plasma6") then ''
    /* nwg-dock Pill/Island styling with Stylix colors - Khanelinix aesthetic */
    
    window {
      background-color: rgba(${config.lib.stylix.colors.base00}, 0.7);
      border-radius: 16px;
      border: 1px solid rgba(${config.lib.stylix.colors.base02}, 0.3);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      box-shadow: 0 4px 16px rgba(0, 0, 0, 0.3);
    }
    
    /* Make hotspot/hover area transparent (invisible) */
    /* nwg-dock creates a separate window for the hotspot area */
    /* Target all possible hotspot element selectors */
    window.hotspot,
    window#hotspot,
    window[class*="hotspot"],
    .hotspot,
    #hotspot,
    *[class*="hotspot"],
    *[id*="hotspot"] {
      background-color: transparent !important;
      border: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      opacity: 0 !important;
    }
    
    /* Also target GTK widget classes that might be used for hotspot */
    widget.hotspot,
    widget#hotspot,
    box.hotspot,
    box#hotspot {
      background-color: transparent !important;
      border: none !important;
      opacity: 0 !important;
    }
    
    #dock {
      padding: 8px;
      spacing: 8px;
      margin: 10px;
      margin-bottom: 10px;
    }
    
    #dock button {
      background-color: rgba(${config.lib.stylix.colors.base01}, 0.5);
      border-radius: 12px;
      padding: 8px;
      border: 1px solid rgba(${config.lib.stylix.colors.base02}, 0.2);
      transition: all 0.2s ease;
      margin: 2px;
    }
    
    #dock button:hover {
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.3);
      transform: scale(1.1);
      box-shadow: 0 2px 8px rgba(${config.lib.stylix.colors.base0D}, 0.3);
    }
    
    #dock button:active {
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.5);
      transform: scale(1.05);
    }
    
    #dock button.running {
      border: 2px solid #${config.lib.stylix.colors.base0D};
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.2);
    }
    
    #dock button.focused {
      background-color: rgba(${config.lib.stylix.colors.base0D}, 0.4);
      border: 2px solid #${config.lib.stylix.colors.base0D};
      box-shadow: 0 2px 8px rgba(${config.lib.stylix.colors.base0D}, 0.4);
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
    
    /* Make hotspot/hover area transparent (invisible) */
    /* nwg-dock creates a separate window for the hotspot area */
    /* Target all possible hotspot element selectors */
    window.hotspot,
    window#hotspot,
    window[class*="hotspot"],
    .hotspot,
    #hotspot,
    *[class*="hotspot"],
    *[id*="hotspot"] {
      background-color: transparent !important;
      border: none !important;
      backdrop-filter: none !important;
      -webkit-backdrop-filter: none !important;
      opacity: 0 !important;
    }
    
    /* Also target GTK widget classes that might be used for hotspot */
    widget.hotspot,
    widget#hotspot,
    box.hotspot,
    box#hotspot {
      background-color: transparent !important;
      border: none !important;
      opacity: 0 !important;
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
    
    #dock button:active {
      background-color: rgba(255, 255, 255, 0.3);
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

