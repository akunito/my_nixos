{ config, lib, pkgs, userSettings, ... }:

{

  imports = [ ../../app/terminal/alacritty.nix
              ../../app/terminal/kitty.nix
            ]
    ++ lib.optional userSettings.wmEnableHyprland (./. + "/../hyprland/hyprland.nix");

  home.packages = with pkgs; [
    flameshot
  ];

  # home.activation = {
  #     createDirectoryMyScripts = ''
  #     #!/bin/sh

  #     # Color variables
  #     RED='\033[0;31m'
  #     GREEN='\033[0;32m'
  #     YELLOW='\033[0;33m'
  #     BLUE='\033[0;34m'
  #     NC='\033[0m' # No Color

  #     echo "=================================== Plasma dotfiles manager ================================"
  #     HOME_PATH="/home/''+userSettings.username+''"
  #     DOTFILES_DIR="''+userSettings.dotfilesDir+''"
  #     USER_PATH="/home/''+userSettings.username+''/.dotfiles-plasma-config/userDotfiles"
  #     SOURCE_PATH="/home/''+userSettings.username+''/.dotfiles-plasma-config/source"
  #     mkdir -p $SOURCE_PATH
  #     mkdir -p $USER_PATH

  #     echo -e "\n''${BLUE}Home path: ----> $HOME_PATH''${NC}"
  #     echo -e "\n''${BLUE}User path (It should contain the Plasma dotfiles that you want to use. The symlinks from your HOME will point here)''${NC}"
  #     echo -e "''${GREEN}--> $USER_PATH''${NC}"
  #     echo -e "\n''${BLUE}Source path (It's a transition directory that contains Plasma dotfiles. If you export your current Plasma dotfiles from HOME, will be backed up here)''${NC}"
  #     echo -e "''${GREEN}--> $SOURCE_PATH''${NC}"

  #     # read -n 1 -s -r -p "Press any key to continue..."

  #     echo -e "\n\n''${BLUE}Export your CURRENT Plasma settings to $SOURCE_PATH''${NC}"
  #     echo -e "''${YELLOW}(Ignore if already exported !.)''${NC}"
  #     echo -e "                            ''${RED}DON'T EXPORT IT TWICE !!!!!''${NC}"

  #     # TODO: Improve this to don't break in any case !
      
  #     while true; do
  #         echo -e "========================== Do you want to Export them? (y/N) (15s timeout)"
  #         read -p "" -t 15 yn || true
  #         case $yn in
  #             [Yy]|[Yy][Ee][Ss])
  #                 echo -e "''${GREEN}yes''${NC}"

  #                 echo -e "\n''${GREEN}=== Backing up your current $SOURCE_PATH to \"''${SOURCE_PATH}.BAK\"''${NC}"
  #                 rm -rf $SOURCE_PATH.BAK && mkdir -p $SOURCE_PATH.BAK
  #                 cp -r $SOURCE_PATH $SOURCE_PATH.BAK/

  #                 echo -e "\n''${BLUE}=== Clearing Source directory $SOURCE_PATH''${NC}"
  #                 rm -rf $SOURCE_PATH && mkdir -p $SOURCE_PATH

  #                 echo -e "\n''${BLUE}=== Exporting your Plasma settings from HOME to $SOURCE_PATH''${NC}"
  #                 $DOTFILES_DIR/user/wm/plasma6/_export_homeDotfiles.sh $SOURCE_PATH

  #                 echo -e "\n''${BLUE}=== Clearing User directory $USER_PATH''${NC}"
  #                 rm -rf $USER_PATH && mkdir -p $USER_PATH

  #                 echo -e "\n''${BLUE}=== Copying your Dotfiles to $USER_PATH''${NC}"
  #                 cp -r $SOURCE_PATH $USER_PATH
  #                 break
  #                 ;;
  #             [Nn]|[Nn][Oo]|"")
  #                 echo -e "''${RED}no''${NC}"
  #                 break
  #                 ;;
  #             *)
  #                 echo -e "''${RED}Invalid option. Please enter y/Y for yes or n/N for no''${NC}"
  #                 ;;
  #         esac
  #     done

  #     echo -e "\n''${BLUE}============= Removing Plasma files at HOME to create symlinks''${NC}"
  #     $DOTFILES_DIR/user/wm/plasma6/_remove_homeDotfiles.sh

  #     echo -e "\n''${BLUE}============= Creating symlinks to directories''${NC}"
  #     # Directories
  #     ln -sf $USER_PATH/autostart $HOME_PATH/.config/autostart
  #     ln -sf $USER_PATH/kde.org $HOME_PATH/.config/kde.org
  #     ln -sf $USER_PATH/kwin $HOME_PATH/.config/kwin
  #     ln -sf $USER_PATH/plasma-workspace $HOME_PATH/.config/plasma-workspace
  #     ln -sf $USER_PATH/share/kded6 $HOME_PATH/.local/kded6
  #     ln -sf $USER_PATH/share/plasma $HOME_PATH/.local/plasma
  #     ln -sf $USER_PATH/share/plasmashell $HOME_PATH/.local/plasmashell
  #     ln -sf $USER_PATH/share/systemsettings $HOME_PATH/.local/systemsettings
      
  #     echo -e "\n''${BLUE}============= Creating symlinks to files''${NC}"
  #     # Files
  #     ln -sf $USER_PATH/plasma-org.kde.plasma.desktop-appletsrc $HOME_PATH/.config/plasma-org.kde.plasma.desktop-appletsrc
  #     ln -sf $USER_PATH/kdeglobals $HOME_PATH/.config/kdeglobals
  #     ln -sf $USER_PATH/kwinrc $HOME_PATH/.config/kwinrc
  #     ln -sf $USER_PATH/krunnerrc $HOME_PATH/.config/krunnerrc
  #     ln -sf $USER_PATH/khotkeysrc $HOME_PATH/.config/khotkeysrc
  #     ln -sf $USER_PATH/kscreenlockerrc $HOME_PATH/.config/kscreenlockerrc
  #     ln -sf $USER_PATH/kcminputrc $HOME_PATH/.config/kcminputrc
  #     ln -sf $USER_PATH/ksmserverrc $HOME_PATH/.config/ksmserverrc
  #     ln -sf $USER_PATH/dolphinrc $HOME_PATH/.config/dolphinrc
  #     ln -sf $USER_PATH/konsolerc $HOME_PATH/.config/konsolerc
  #     ln -sf $USER_PATH/kglobalshortcutsrc $HOME_PATH/.config/kglobalshortcutsrc
  #     ln -sf $USER_PATH/kactivitymanagerd-pluginsrc $HOME_PATH/.config/kactivitymanagerd-pluginsrc
  #     ln -sf $USER_PATH/kactivitymanagerd-statsrc $HOME_PATH/.config/kactivitymanagerd-statsrc
  #     ln -sf $USER_PATH/kactivitymanagerd-switcher $HOME_PATH/.config/kactivitymanagerd-switcher
  #     ln -sf $USER_PATH/kactivitymanagerdrc $HOME_PATH/.config/kactivitymanagerdrc
  #     ln -sf $USER_PATH/kcmfonts $HOME_PATH/.config/kcmfonts
  #     ln -sf $USER_PATH/kded5rc $HOME_PATH/.config/kded5rc
  #     ln -sf $USER_PATH/kded6rc $HOME_PATH/.config/kded6rc
  #     ln -sf $USER_PATH/kfontinstuirc $HOME_PATH/.config/kfontinstuirc
  #     ln -sf $USER_PATH/kwinrulesrc $HOME_PATH/.configkwinrulesrc
  #     ln -sf $USER_PATH/plasma-localerc $HOME_PATH/.config/plasma-localerc
  #     ln -sf $USER_PATH/plasmanotifyrc $HOME_PATH/.config/plasmanotifyrc
  #     ln -sf $USER_PATH/plasmarc $HOME_PATH/.config/plasmarc
  #     ln -sf $USER_PATH/plasmashellrc $HOME_PATH/.config/plasmashellrc
  #     ln -sf $USER_PATH/plasmawindowed-appletsrc $HOME_PATH/.config/plasmawindowed-appletsrc
  #     ln -sf $USER_PATH/plasmawindowedrc $HOME_PATH/.config/plasmawindowedrc
  #     ln -sf $USER_PATH/powerdevilrc $HOME_PATH/.config/powerdevilrc
  #     ln -sf $USER_PATH/powermanagementprofilesrc $HOME_PATH/.config/powermanagementprofilesrc
  #     ln -sf $USER_PATH/spectaclerc $HOME_PATH/.config/spectaclerc
  #     ln -sf $USER_PATH/systemsettingsrc $HOME_PATH/.config/systemsettingsrc

  #     ln -sf $USER_PATH/share/aurorae/themes $HOME_PATH/.local/aurorae
  #     ln -sf $USER_PATH/share/color-schemes $HOME_PATH/.local/color-schemes

  #     echo -e "\n''${BLUE}============= End''${NC}"
  #     '';
  #   };
}