# LXC mailer Profile Configuration
# Production profile for mail service and uptime monitoring (Kuma)
# Hosts docker containers for mail services and kuma monitoring

let
  base = import ./LXC-base-config.nix;
in
{
  systemSettings = base.systemSettings // {
    hostname = "mailerwatcher";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles LXC_mailer -s -u";
    systemStateVersion = "25.11";

    # Firewall - Add SMTP port for mail service
    allowedTCPPorts = [
      22    # SSH
      25    # SMTP (mail service)
      80    # HTTP
      443   # HTTPS
      3000  # Web apps
      3001  # Kuma monitoring
      9100  # Prometheus Node Exporter
      9092  # cAdvisor (Docker metrics)
    ];

    # ============================================================================
    # AUTO-UPGRADE SETTINGS (Stable Profile - Weekly Saturday 07:35)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateOnCalendar = "Sat *-*-* 07:35:00";
    autoUpgradeRestartDocker = false;
    autoUserUpdateBranch = "release-25.11"; # Stable home-manager branch
  };

  userSettings = base.userSettings // {
    homeStateVersion = "25.11";
  };
}
