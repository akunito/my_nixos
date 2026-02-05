# LXC portfolioprod Profile Configuration
# Production profile for portfolio service

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "portfolioprod";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_portfolioprod -s -u";
    systemStateVersion = "25.11";
    serverEnv = "PROD"; # Production environment

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:30)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:30:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11"; # Stable home-manager branch
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";

    # Home packages (extends base packages)
    homePackages = pkgs: pkgs-unstable:
      (base.userSettings.homePackages pkgs pkgs-unstable) ++ [
        pkgs.python3Packages.uptime-kuma-api # Python wrapper for Uptime Kuma API
      ];
  };
}
