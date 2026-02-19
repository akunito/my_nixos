# Shared SSH host definitions for workstations
# Generates ~/.ssh/config via Home Manager programs.ssh
# Controlled by systemSettings.sshHostsManaged flag
{ lib, userSettings, systemSettings, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "homelab" = {
        hostname = "192.168.8.80";
        user = "akunito";
        forwardAgent = true;
      };
      "vps" = {
        hostname = "91.211.27.37";
        user = "root";
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
        user = "truenas_admin";
        forwardAgent = true;
      };
      "github.com" = {
        hostname = "github.com";
        user = "akunito";
        identityFile = "~/.ssh/id_ed25519";
        extraOptions.AddKeysToAgent = "yes";
      };
      "ssh-leftyworkout-test.akunito.com" = {
        user = "admin";
        proxyCommand = "cloudflared access ssh --hostname %h";
        forwardAgent = true;
      };
      "leftyworkoutTest" = {
        hostname = "192.168.8.87";
        user = "admin";
        forwardAgent = true;
      };
      "portfolioprod" = {
        hostname = "192.168.8.88";
        user = "admin";
        forwardAgent = true;
      };
    };
  };
}
