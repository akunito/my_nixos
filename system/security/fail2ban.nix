{ ... }:

{
  services.fail2ban = {
    enable = true;

    # Global settings
    maxretry = 5;               # Number of failures before banning
    ignoreIP = [
      "127.0.0.1/8"               # localhost
      "::1/128"                   # IPv6 localhost
      "172.26.5.1/32"             # WG pfsense
      "fd86:ea04:1111::1/128"     # WG pfsense ipv6
      "172.26.3.155/16"           # WG server network
      "fd86:ea04:1111::155/64"    # WG server IPv6 network
      "::1/128"                   # IPv6 localhost    ];
    ];
    bantime = "24h";            # Ban duration
    bantime-increment = {
      enable = true; # Enable increment of bantime after each violation
      multipliers = "1 2 4 8 16 32 64";
      maxtime = "168h"; # Do not ban for more than 1 week
      overalljails = true; # Calculate the bantime based on all the violations
    };

    jails = {
      sshd = {
        settings = {
          enabled = true;
          port = "ssh,22";
          filter = "sshd[mode=aggressive]";
          findtime = "600";
          maxretry = 3;
          logpath = "/var/log/auth.log";
        };
      };

      nginx-botsearch = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-botsearch";
          findtime = "600";
          maxretry = 5;
          logpath = "/var/log/nginx/access.log";
        };
      };

      nginx-http-auth = {
        settings = {
          enabled = true;
          port = "http,https";
          filter = "nginx-http-auth";
          findtime = "600";
          maxretry = 5;
          logpath = "/var/log/nginx/error.log";
        };
      };

      gitea = {
        settings = {
          enabled = true;
          port = "http,https,3000";
          filter = "gitea";
          findtime = "600";
          maxretry = 5;
          logpath = "/var/log/gitea/gitea.log";
        };
      };
    };
  };
}
