# Shared SSH host definitions for workstations
# Generates ~/.ssh/config via Home Manager programs.ssh
# Controlled by systemSettings.sshHostsManaged flag
{ lib, userSettings, systemSettings, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "homelab" = {
        hostname = "192.168.8.80";
        user = "akunito";
        forwardAgent = true;
      };
      "vps" = {
        hostname = "100.64.0.6"; # VPS_PROD via Tailscale (Netcup RS 4000 G12)
        user = "akunito";
        port = 56777;
        forwardAgent = true;
      };
      "planePROD-nixos" = {
        hostname = "192.168.8.86";
        user = "akunito";
        forwardAgent = true;
      };
      "mailerWatcher" = {
        hostname = "192.168.8.89";
        user = "akunito";
        forwardAgent = true;
      };
      "pve" = {
        hostname = "192.168.8.82";
        user = "root";
        forwardAgent = true;
      };
      "aga-laptop" = {
        hostname = "192.168.8.78";
        user = "aga";
        forwardAgent = true;
      };
      "truenas" = {
        hostname = "192.168.20.200";
        user = "akunito";  # NixOS NAS uses akunito (was truenas_admin)
        forwardAgent = true;
      };
      "github.com" = {
        hostname = "github.com";
        user = "akunito";
        identityFile = "~/.ssh/id_ed25519";
        extraOptions.AddKeysToAgent = "yes";
      };
      # leftyworkoutTest and portfolioprod LXCs (192.168.8.87, 192.168.8.88)
      # migrated to VPS — use "ssh vps" instead
    };
  };
}
