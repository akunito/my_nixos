# LXC liftcraftTEST Profile Configuration
# Test profile based on LXC_plane

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "leftyworkoutTEST";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_liftcraftTEST -s -u";
    systemStateVersion = "25.11";
    serverEnv = "TEST"; # Test environment

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:25)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:25:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11"; # Stable home-manager branch
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
