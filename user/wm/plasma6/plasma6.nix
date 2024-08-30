{ config, pkgs, userSettings, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  # home.activation = { # FOR TEST
  #     createDirectoryMyScripts = ''
  #     #!/bin/sh
  #     echo "\nRunning home.activation script TEST <<<<<<<<<<<<<<<<<<< ..." 

  #     echo "Create symlinks to Plasma settings files on my Git repo"
  #     echo "Building paths from userSettings variables (username & dotfilesDir)"
  #     echo "Home path ----> /home/''+userSettings.username+''/..."
  #     echo "Source path --> ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/..."

  #     # Directories
  #     ln -sf ''userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/autostart /home/''+userSettings.username+''/.config/testautostart 
      
  #     # Files
  #     ln -sf ''userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kdeglobals /home/''+userSettings.username+''/.config/testkdeglobals 
  #     '';
  #   };

  # home.activation = {
  #     createDirectoryMyScripts = ''
  #     #!/bin/sh
  #     echo "\nRunning home.activation script..." 

  #     echo "Create symlinks to Plasma settings files on my Git repo"

  #     # Directories
  #     ln -sf /home/''+userSettings.username+''/.config/autostart ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/autostart
  #     ln -sf /home/''+userSettings.username+''/.config/kde.org ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kde.org
  #     ln -sf /home/''+userSettings.username+''/.config/kwin ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kwin
  #     ln -sf /home/''+userSettings.username+''/.config/plasma-workspace ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasma-workspace
  #     ln -sf /home/''+userSettings.username+''/.config/spectacle ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/spectacle
  #     ln -sf /home/''+userSettings.username+''/.local/share/kded6 ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kded6
  #     ln -sf /home/''+userSettings.username+''/.local/share/plasma ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasma
  #     ln -sf /home/''+userSettings.username+''/.local/share/plasmashell ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasmashell
  #     ln -sf /home/''+userSettings.username+''/.local/share/systemsettings ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/systemsettings
      
  #     # Files
  #     ln -sf /home/''+userSettings.username+''/.config/plasma-org.kde.plasma.desktop-appletsrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasma-org.kde.plasma.desktop-appletsrc
  #     ln -sf /home/''+userSettings.username+''/.config/kdeglobals ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kdeglobals
  #     ln -sf /home/''+userSettings.username+''/.config/kwinrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kwinrc
  #     ln -sf /home/''+userSettings.username+''/.config/krunnerrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/krunnerrc
  #     ln -sf /home/''+userSettings.username+''/.config/khotkeysrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/khotkeysrc
  #     ln -sf /home/''+userSettings.username+''/.config/kscreenlockerrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kscreenlockerrc
  #     ln -sf /home/''+userSettings.username+''/.config/kwalletrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kwalletrc
  #     ln -sf /home/''+userSettings.username+''/.config/kcminputrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kcminputrc
  #     ln -sf /home/''+userSettings.username+''/.config/ksmserverrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/ksmserverrc
  #     ln -sf /home/''+userSettings.username+''/.config/dolphinrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/dolphinrc
  #     ln -sf /home/''+userSettings.username+''/.config/konsolerc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/konsolerc
  #     ln -sf /home/''+userSettings.username+''/.config/kglobalshortcutsrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kglobalshortcutsrc
  #     ln -sf /home/''+userSettings.username+''/.config/kactivitymanagerd-pluginsrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kactivitymanagerd-pluginsrc
  #     ln -sf /home/''+userSettings.username+''/.config/kactivitymanagerd-statsrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kactivitymanagerd-statsrc
  #     ln -sf /home/''+userSettings.username+''/.config/kactivitymanagerd-switcher ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kactivitymanagerd-switcher
  #     ln -sf /home/''+userSettings.username+''/.config/kactivitymanagerdrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kactivitymanagerdrc
  #     ln -sf /home/''+userSettings.username+''/.config/kcmfonts ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kcmfonts
  #     ln -sf /home/''+userSettings.username+''/.config/kded5rc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kded5rc
  #     ln -sf /home/''+userSettings.username+''/.config/kded6rc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kded6rc
  #     ln -sf /home/''+userSettings.username+''/.config/kfontinstuirc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kfontinstuirc
  #     ln -sf /home/''+userSettings.username+''/.config/kwinrulesrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/kwinrulesrc
  #     ln -sf /home/''+userSettings.username+''/.config/plasma-localerc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasma-localerc
  #     ln -sf /home/''+userSettings.username+''/.config/plasmanotifyrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasmanotifyrc
  #     ln -sf /home/''+userSettings.username+''/.config/plasmarc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasmarc
  #     ln -sf /home/''+userSettings.username+''/.config/plasmashellrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasmashellrc
  #     ln -sf /home/''+userSettings.username+''/.config/plasmawindowed-appletsrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasmawindowed-appletsrc
  #     ln -sf /home/''+userSettings.username+''/.config/plasmawindowedrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/plasmawindowedrc
  #     ln -sf /home/''+userSettings.username+''/.config/powerdevilrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/powerdevilrc
  #     ln -sf /home/''+userSettings.username+''/.config/powermanagementprofilesrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/powermanagementprofilesrc
  #     ln -sf /home/''+userSettings.username+''/.config/spectaclerc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/spectaclerc
  #     ln -sf /home/''+userSettings.username+''/.config/systemsettingsrc ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/systemsettingsrc

  #     ln -sf /home/''+userSettings.username+''/.local/share/aurorae/themes ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/aurorae
  #     ln -sf /home/''+userSettings.username+''/.local/share/color-schemes ''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''/color-schemes
  #     '';
  #   };
}
