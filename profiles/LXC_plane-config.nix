# LXC Default Profile Configuration
# Imports base and sets default hostname

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "planePROD-nixos";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_plane -s -u";
    systemStateVersion = "25.11";
    serverEnv = "PROD"; # Production environment

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:15)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:15:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11"; # Stable home-manager branch
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
