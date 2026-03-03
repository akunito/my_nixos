{ lib, pkgs, systemSettings, userSettings, ... }:

let
  sshPort = toString (systemSettings.sshPort or 22);
  username = userSettings.username or "akunito";
  minecraftLogPath = "/home/${username}/.homelab/minecraft/data/logs/latest.log";

  # Custom fail2ban filter for Minecraft — detects rapid reconnections
  # (brute-force EasyAuth login or bot scanning on offline-mode servers)
  minecraftFilter = pkgs.writeText "minecraft.conf" ''
    [INCLUDES]
    before = common.conf

    [Definition]
    # Match connection lines containing IP: PlayerName[/1.2.3.4:12345] logged in
    failregex = ^\[.*\] \[Server thread/INFO\]:.*\[/<HOST>:\d+\] logged in
    ignoreregex =

    [Init]
    # Minecraft latest.log uses [HH:MM:SS] with no date — use file mtime
    datepattern = \[%%H:%%M:%%S\]
  '';
in

{
  # Install custom Minecraft fail2ban filter
  environment.etc."fail2ban/filter.d/minecraft.conf" = lib.mkIf (systemSettings.fail2banMinecraftJailEnable or false) {
    source = minecraftFilter;
  };

  services.fail2ban = {
    enable = systemSettings.fail2banEnable or false;

    # Global settings
    maxretry = 5;               # Number of failures before banning
    ignoreIP = [
      "127.0.0.1/8"               # localhost
      "::1/128"                   # IPv6 localhost
      "172.26.5.1/32"             # WG pfsense
      "fd86:ea04:1111::1/128"     # WG pfsense ipv6
      "172.26.3.155/16"           # WG server network
      "fd86:ea04:1111::155/64"    # WG server IPv6 network
      "192.168.8.96/32"           # DESK (primary)
      "192.168.8.97/32"           # DESK (bond)
      "192.168.8.92/32"           # LAPTOP_X13 (primary)
      "192.168.8.93/32"           # LAPTOP_X13 (alt)
    ]
    # Tailscale CGNAT range — prevent VPN connections from being banned
    ++ lib.optionals (systemSettings.tailscaleEnable or false) [
      "100.64.0.0/10"             # Tailscale CGNAT range
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
          port = "ssh,${sshPort}";
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
          enabled = systemSettings.fail2banGiteaJailEnable or false;
          port = "http,https,3000";
          filter = "gitea";
          findtime = "600";
          maxretry = 5;
          logpath = "/var/log/gitea/gitea.log";
        };
      };

      minecraft = {
        settings = {
          enabled = systemSettings.fail2banMinecraftJailEnable or false;
          port = "25565";
          filter = "minecraft";
          findtime = "600";       # 10 minute window
          maxretry = 5;           # 5 connections before ban
          logpath = minecraftLogPath;
          backend = "auto";
        };
      };
    };
  };
}
