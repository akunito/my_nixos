{ config, pkgs, userSettings, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ];

  home.packages = with pkgs; [
    flameshot
  ];

  home.activation = {
      createDirectoryMyScripts = ''
      #!/bin/sh
      echo "=================================== Plasma dotfiles manager ================================"
      HOME_PATH="/home/''+userSettings.username+''"
      USER_PATH="''+userSettings.dotfilesDir+''/user/wm/plasma6/''+userSettings.username+''"
      SOURCE_PATH="''+userSettings.dotfilesDir+''/user/wm/plasma6/source"
      mkdir -p $SOURCE_PATH
      mkdir -p $USER_PATH

      echo "Home path: ----> $HOME_PATH"
      echo "User path (It should contain the Plasma dotfiles that you want to use. The symlinks from your HOME will point here)"
      echo "--> $USER_PATH"
      echo "Source path (It's a transition directory that contain Plasma dotfiles. If you import your current Plasma dotfiles from HOME, will be backed up here)"
      echo "--> $SOURCE_PATH"

      # Ask user if Backup is needed
      read -p "Do you want to backup your Plasma settings dotfiles to $SOURCE_PATH ? (y/N) (10s timeout) " -t 10 yn
      case $yn in
          [Yy]|[Yy][Ee][Ss])
              echo "=== Cleaning destination directory $SOURCE_PATH excluding .sh files"
              find $SOURCE_PATH -mindepth 1 ! -name "*.sh" -exec rm -rf {} +

              echo "=== Importing your Plasma settings from HOME to $SOURCE_PATH"
              $SOURCE_PATH/_import_homeDotfiles.sh $SOURCE_PATH

              echo "=== Cleaning the User directory $USER_PATH, excluding .sh files"
              find $USER_PATH -mindepth 1 ! -name "*.sh" -exec rm -rf {} +

              echo "=== Copying your Dotfiles to $USER_PATH"
              cp -r $SOURCE_PATH/* $USER_PATH
              ;;
          "")
              ;;
          *)
              ;;
      esac

      echo "\n============= Removing files on HOME to create symlinks"
      ~/.dotfiles/user/wm/plasma6/source/_remove_homeDotfiles.sh

      echo "\n============= Creating symlinks to directories"
      # Directories
      ln -sf $USER_PATH/autostart $HOME_PATH/.config/autostart
      ln -sf $USER_PATH/kde.org $HOME_PATH/.config/kde.org
      ln -sf $USER_PATH/kwin $HOME_PATH/.config/kwin
      ln -sf $USER_PATH/plasma-workspace $HOME_PATH/.config/plasma-workspace
      ln -sf $USER_PATH/share/kded6 $HOME_PATH/.local/kded6
      ln -sf $USER_PATH/share/plasma $HOME_PATH/.local/plasma
      ln -sf $USER_PATH/share/plasmashell $HOME_PATH/.local/plasmashell
      ln -sf $USER_PATH/share/systemsettings $HOME_PATH/.local/systemsettings
      
      echo "\n============= Creating symlinks to files"
      # Files
      ln -sf $USER_PATH/plasma-org.kde.plasma.desktop-appletsrc $HOME_PATH/.config/plasma-org.kde.plasma.desktop-appletsrc
      ln -sf $USER_PATH/kdeglobals $HOME_PATH/.config/kdeglobals
      ln -sf $USER_PATH/kwinrc $HOME_PATH/.config/kwinrc
      ln -sf $USER_PATH/krunnerrc $HOME_PATH/.config/krunnerrc
      ln -sf $USER_PATH/khotkeysrc $HOME_PATH/.config/khotkeysrc
      ln -sf $USER_PATH/kscreenlockerrc $HOME_PATH/.config/kscreenlockerrc
      ln -sf $USER_PATH/kcminputrc $HOME_PATH/.config/kcminputrc
      ln -sf $USER_PATH/ksmserverrc $HOME_PATH/.config/ksmserverrc
      ln -sf $USER_PATH/dolphinrc $HOME_PATH/.config/dolphinrc
      ln -sf $USER_PATH/konsolerc $HOME_PATH/.config/konsolerc
      ln -sf $USER_PATH/kglobalshortcutsrc $HOME_PATH/.config/kglobalshortcutsrc
      ln -sf $USER_PATH/kactivitymanagerd-pluginsrc $HOME_PATH/.config/kactivitymanagerd-pluginsrc
      ln -sf $USER_PATH/kactivitymanagerd-statsrc $HOME_PATH/.config/kactivitymanagerd-statsrc
      ln -sf $USER_PATH/kactivitymanagerd-switcher $HOME_PATH/.config/kactivitymanagerd-switcher
      ln -sf $USER_PATH/kactivitymanagerdrc $HOME_PATH/.config/kactivitymanagerdrc
      ln -sf $USER_PATH/kcmfonts $HOME_PATH/.config/kcmfonts
      ln -sf $USER_PATH/kded5rc $HOME_PATH/.config/kded5rc
      ln -sf $USER_PATH/kded6rc $HOME_PATH/.config/kded6rc
      ln -sf $USER_PATH/kfontinstuirc $HOME_PATH/.config/kfontinstuirc
      ln -sf $USER_PATH/kwinrulesrc $HOME_PATH/.configkwinrulesrc
      ln -sf $USER_PATH/plasma-localerc $HOME_PATH/.config/plasma-localerc
      ln -sf $USER_PATH/plasmanotifyrc $HOME_PATH/.config/plasmanotifyrc
      ln -sf $USER_PATH/plasmarc $HOME_PATH/.config/plasmarc
      ln -sf $USER_PATH/plasmashellrc $HOME_PATH/.config/plasmashellrc
      ln -sf $USER_PATH/plasmawindowed-appletsrc $HOME_PATH/.config/plasmawindowed-appletsrc
      ln -sf $USER_PATH/plasmawindowedrc $HOME_PATH/.config/plasmawindowedrc
      ln -sf $USER_PATH/powerdevilrc $HOME_PATH/.config/powerdevilrc
      ln -sf $USER_PATH/powermanagementprofilesrc $HOME_PATH/.config/powermanagementprofilesrc
      ln -sf $USER_PATH/spectaclerc $HOME_PATH/.config/spectaclerc
      ln -sf $USER_PATH/systemsettingsrc $HOME_PATH/.config/systemsettingsrc

      ln -sf $USER_PATH/share/aurorae/themes $HOME_PATH/.local/aurorae
      ln -sf $USER_PATH/share/color-schemes $HOME_PATH/.local/color-schemes
      '';
    };
}
