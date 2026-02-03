# Cloudflare Tunnel Service (Remotely Managed)
# Token stored at /etc/secrets/cloudflared-token
#
# Setup:
#   sudo mkdir -p /etc/secrets
#   echo 'YOUR_TUNNEL_TOKEN' | sudo tee /etc/secrets/cloudflared-token
#   sudo chmod 600 /etc/secrets/cloudflared-token
#   sudo chown cloudflared:cloudflared /etc/secrets/cloudflared-token

{ pkgs, lib, systemSettings, ... }:

lib.mkIf (systemSettings.cloudflaredEnable or false) {
  environment.systemPackages = [ pkgs.cloudflared ];

  users.users.cloudflared = {
    isSystemUser = true;
    group = "cloudflared";
  };
  users.groups.cloudflared = {};

  systemd.services.cloudflared = {
    description = "Cloudflare Tunnel";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "cloudflared";
      Group = "cloudflared";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token $(cat /etc/secrets/cloudflared-token)'";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadOnlyPaths = [ "/etc/secrets/cloudflared-token" ];
    };
  };
}
