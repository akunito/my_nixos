{ config, pkgs, lib, userSettings, systemSettings, ... }:

let
  # Theme content (Stylix or fallback)
  themeContent = if systemSettings.stylixEnable == true then (let
      inherit (config.lib.stylix.colors) base00 base01 base02 base03 base04 base05 base06 base07
                                        base08 base09 base0A base0B base0C base0D base0E base0F;
    in ''
      * {
        bg-col:  #${base00}E6;
        bg-col-light:  #${base01}E6;
        border-col:  #${base02};
        selected-col:  #${base0D};
        blue:  #${base0D};
        fg-col:  #${base07};
        fg-col2:  #${base05};
        grey:  #${base04};
        width: 80;
        font: "${userSettings.font} 12";
      }
      
      window {
        background-color: @bg-col;
        border-radius: 20px;
        border: 0px;
        padding: 0px;
        /* backdrop-filter: blur(10px); */
        /* -webkit-backdrop-filter: blur(10px); */
      }
      
      mainbox {
        border: 0px;
        padding: 0px;
      }
      
      inputbar {
        children: [prompt,entry];
        border: 0px;
        border-radius: 20px 20px 0px 0px;
        padding: 8px;
        background-color: @bg-col-light;
      }
      
      prompt {
        background-color: @selected-col;
        padding: 6px;
        text-color: @fg-col;
        border-radius: 10px;
        margin: 5px;
      }
      
      textbox-prompt-colon {
        expand: false;
        str: ":";
      }
      
      entry {
        padding: 6px;
        margin: 5px;
        text-color: @fg-col;
        background-color: @bg-col-light;
      }
      
      listview {
        border: 0px;
        border-radius: 0px 0px 20px 20px;
        padding: 4px;
        margin: 0px;
        lines: 12;
        columns: 1;
      }
      
      element {
        border: 0px;
        padding: 4px;
        background-color: transparent;
      }
      
      element selected {
        background-color: @selected-col;
        border-radius: 8px;
      }
      
      element-text {
        background-color: inherit;
        text-color: @fg-col;
      }
      
      element-icon {
        background-color: inherit;
      }
    '') else ''
      * {
        bg-col:  #1e1e2eE6;
        bg-col-light:  #313244E6;
        border-col:  #45475a;
        selected-col:  #89b4fa;
        blue:  #89b4fa;
        fg-col:  #cdd6f4;
        fg-col2:  #bac2de;
        grey:  #6c7086;
        width: 80;
        font: "${userSettings.font} 12";
      }
      
      window {
        background-color: @bg-col;
        border-radius: 20px;
        border: 0px;
        padding: 0px;
        /* backdrop-filter: blur(10px); */
        /* -webkit-backdrop-filter: blur(10px); */
      }
      
      mainbox {
        border: 0px;
        padding: 0px;
      }
      
      inputbar {
        children: [prompt,entry];
        border: 0px;
        border-radius: 20px 20px 0px 0px;
        padding: 8px;
        background-color: @bg-col-light;
      }
      
      prompt {
        background-color: @selected-col;
        padding: 6px;
        text-color: @fg-col;
        border-radius: 10px;
        margin: 5px;
      }
      
      textbox-prompt-colon {
        expand: false;
        str: ":";
      }
      
      entry {
        padding: 6px;
        margin: 5px;
        text-color: @fg-col;
        background-color: @bg-col-light;
      }
      
      listview {
        border: 0px;
        border-radius: 0px 0px 20px 20px;
        padding: 4px;
        margin: 0px;
        lines: 12;
        columns: 1;
      }
      
      element {
        border: 0px;
        padding: 4px;
        background-color: transparent;
      }
      
      element selected {
        background-color: @selected-col;
        border-radius: 8px;
      }
      
      element-text {
        background-color: inherit;
        text-color: @fg-col;
      }
      
      element-icon {
        background-color: inherit;
      }
    '';
in {
  # Write theme file manually
  home.file.".config/rofi/themes/custom.rasi" = {
    text = themeContent;
  };

  # Write config.rasi manually (don't use programs.rofi to avoid conflict)
  # The rofi package is already installed via home.packages in default.nix
  home.file.".config/rofi/config.rasi" = {
    text = ''
      configuration {
        columns: 1;
        combi-modi: "drun,run,window,filebrowser";
        display-combi: "";
        filebrowser-dir: "~";
        fixed-num-lines: true;
        font: "${userSettings.font} 12";
        icon-theme: "Papirus";
        lines: 12;
        location: 0;
        modi: "combi,drun,run,window";
        show-icons: true;
        show-match: true;
        sidebar-mode: false;
        terminal: "${userSettings.term}";
        width: 80;
        xoffset: 0;
        yoffset: 0;
      }
      @theme "themes/custom.rasi"
    '';
  };
}
