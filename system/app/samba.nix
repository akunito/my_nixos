{ config, pkgs, lib, systemSettings, ... }:

{

    services.samba = {
        enable = true;
        openFirewall = true;
        settings = {
            global = {
                "workgroup" = "WORKGROUP";
                "server string" = "NixOS Samba Server";
                "netbios name" = "nixos-samba";
                "security" = "user";
                "hosts allow" = "192.168.122.108 192.168.122. 192.168.8. 127.0.0.1 localhost"; # Ensure this matches your local network
                "hosts deny" = "0.0.0.0/0";
                "guest account" = "nobody";
                "map to guest" = "bad user";
            };
            "downloads" = {
                "path" = "/mnt/DATA/Downloads";
                "browseable" = "yes";
                "read only" = "no";
                "guest ok" = "no"; # It's generally safer to disable guest access on private shares
                "valid users" = "akunito"; # Specify which users can access this share
                "force user" = "akunito";
                "create mask" = "0664";
                "directory mask" = "0775";
            };
            "games" = {
                "path" = "/mnt/DATA/Games";
                "browseable" = "yes";
                "read only" = "no";
                "guest ok" = "no";
                "valid users" = "akunito";
                "force user" = "akunito";
                "create mask" = "0664";
                "directory mask" = "0775";
            };
        };
    };

    services.samba-wsdd = {
        enable = true;
        openFirewall = true;
    };

}