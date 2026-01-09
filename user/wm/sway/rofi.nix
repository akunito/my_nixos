{ config, pkgs, lib, userSettings, systemSettings, ... }:

let
  # Theme content (Stylix or fallback)
  # CRITICAL: Check if Stylix is actually available (not just enabled)
  # Stylix is disabled for Plasma 6 even if stylixEnable is true
  # However, if SwayFX is enabled via enableSwayForDESK, Stylix should be enabled for SwayFX
  themeContent = if (systemSettings.stylixEnable == true && (userSettings.wm != "plasma6" || systemSettings.enableSwayForDESK == true)) then (let
      inherit (config.lib.stylix.colors) base00 base01 base02 base03 base04 base05 base06 base07
                                        base08 base09 base0A base0B base0C base0D base0E base0F;
    in ''
      * {
        bg-col:  #${base00}FF;
        bg-col-light:  #${base01}FF;
        border-col:  #${base02};
        selected-col:  #${base0D};
        blue:  #${base0D};
        fg-col:  #${base07};
        fg-col2:  #${base05};
        grey:  #${base04};
        width: 38;
        font: "JetBrainsMono Nerd Font 14";
      }
      
      window {
        background-color: @bg-col;
        border-radius: 20px;
        border: 2px;
        border-color: @border-col;
        padding: 0px;
        width: 38%;
        transparency: "real";
      }
      
      mainbox {
        border: 0px;
        padding: 12px;
        background-color: @bg-col;
      }
      
      inputbar {
        children: [prompt,entry];
        border: 0px;
        border-radius: 20px 20px 0px 0px;
        padding: 12px;
        background-color: @bg-col-light;
        margin: 0px 0px 8px 0px;
      }
      
      prompt {
        background-color: @selected-col;
        padding: 10px 14px;
        text-color: @fg-col;
        border-radius: 12px;
        margin: 0px 8px 0px 0px;
      }
      
      textbox-prompt-colon {
        expand: false;
        str: ":";
      }
      
      entry {
        padding: 10px 14px;
        margin: 0px;
        text-color: @fg-col;
        background-color: @bg-col-light;
        border-radius: 12px;
      }
      
      listview {
        border: 0px;
        border-radius: 0px 0px 20px 20px;
        padding: 8px;
        margin: 0px;
        lines: 12;
        columns: 1;
        spacing: 4px;
        background-color: @bg-col;
      }
      
      element {
        border: 0px;
        padding: 12px 16px;
        background-color: transparent;
        text-color: @fg-col;
      }
      
      element selected {
        background-color: @selected-col;
        border-radius: 12px;
        text-color: @fg-col;
      }
      
      element-text {
        background-color: inherit;
        text-color: inherit;
        vertical-align: 0.5;
      }
      
      element-icon {
        background-color: inherit;
        size: 24px;
      }
    '') else ''
      * {
        bg-col:  #1e1e2eFF;
        bg-col-light:  #313244FF;
        border-col:  #45475a;
        selected-col:  #89b4fa;
        blue:  #89b4fa;
        fg-col:  #cdd6f4;
        fg-col2:  #bac2de;
        grey:  #6c7086;
        width: 38;
        font: "JetBrainsMono Nerd Font 14";
      }
      
      window {
        background-color: @bg-col;
        border-radius: 20px;
        border: 2px;
        border-color: @border-col;
        padding: 0px;
        width: 38%;
      }
      
      mainbox {
        border: 0px;
        padding: 12px;
      }
      
      inputbar {
        children: [prompt,entry];
        border: 0px;
        border-radius: 20px 20px 0px 0px;
        padding: 12px;
        background-color: @bg-col-light;
        margin: 0px 0px 8px 0px;
      }
      
      prompt {
        background-color: @selected-col;
        padding: 10px 14px;
        text-color: @fg-col;
        border-radius: 12px;
        margin: 0px 8px 0px 0px;
      }
      
      textbox-prompt-colon {
        expand: false;
        str: ":";
      }
      
      entry {
        padding: 10px 14px;
        margin: 0px;
        text-color: @fg-col;
        background-color: @bg-col-light;
        border-radius: 12px;
      }
      
      listview {
        border: 0px;
        border-radius: 0px 0px 20px 20px;
        padding: 8px;
        margin: 0px;
        lines: 12;
        columns: 1;
        spacing: 4px;
      }
      
      element {
        border: 0px;
        padding: 12px 16px;
        background-color: transparent;
        text-color: @fg-col;
      }
      
      element selected {
        background-color: @selected-col;
        border-radius: 12px;
        text-color: @fg-col;
      }
      
      element-text {
        background-color: inherit;
        text-color: inherit;
        vertical-align: 0.5;
      }
      
      element-icon {
        background-color: inherit;
        size: 24px;
      }
    '';
in {
  # Write theme file manually (preserve Stylix integration)
  home.file.".config/rofi/themes/custom.rasi" = {
    text = themeContent;
  };

  # Use programs.rofi module for proper plugin support and ROFI_PLUGIN_PATH configuration
  programs.rofi = {
    enable = true;
    package = pkgs.rofi;  # Standard package with native Wayland support
    theme = "themes/custom";  # Explicitly load custom.rasi theme
    
    # Plugins must be in programs.rofi.plugins (NOT home.packages) for ROFI_PLUGIN_PATH to work
    plugins = with pkgs; [
      rofi-calc
      rofi-emoji
    ];
    
    # Migrate existing config.rasi settings to extraConfig
    extraConfig = {
      columns = 1;
      combi-modi = "drun,run,window,filebrowser,calc,emoji";
      display-combi = "";
      display-window = "";
      filebrowser-dir = "~";
      fixed-num-lines = true;
      font = "JetBrainsMono Nerd Font 14";
      icon-theme = "Papirus";
      lines = 12;
      location = 0;
      modi = "combi,drun,run,window,calc,emoji";
      show-icons = true;
      show-match = true;
      sidebar-mode = false;
      terminal = "${userSettings.term}";
      width = 38;
      window-format = "{t}";
      xoffset = 0;
      yoffset = 0;
    };
  };
}
