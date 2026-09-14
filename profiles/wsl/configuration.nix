# NixOS-WSL module set (profile = "wsl"). Used by DESK_W11.
# Windows owns: desktop, GPU, browser, Nextcloud client, Tailscale, terminal UI.
# WSL owns: shell, git, Claude Code + claude-sync, docker, NFS to the NAS, ssh.
# Runbook: docs/akunito/infrastructure/desk-w11-wsl.md

{ lib, pkgs, pkgs-unstable, systemSettings, userSettings, inputs, ... }:

let
  winUser = systemSettings.wslWindowsUser or "";
  home = "/home/${userSettings.username}";
in
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ../../system/shell/env-profile.nix # ENV_PROFILE=DESK_W11
    ../../system/hardware/systemd.nix # journald limits
    ../../system/security/sudo.nix
    ../../system/security/gpg.nix # gpg-agent as ssh agent (pinentry-curses via gpgPinentryCurses)
    ../../system/security/firewall.nix
    ../../system/security/nix-access-token.nix # GitHub PAT → per-user nix.conf
    ../../system/security/restic.nix # restic wrapper + home_backup timer (self-gated on homeBackupEnable)
    ../../system/hardware/nfs_client.nix # NAS mounts (nfsMounts/nfsAutoMounts) + stale-mount reaper
    (import ../../system/app/docker.nix {
      storageDriver = null;
      userlandProxy = true;
      inherit pkgs pkgs-unstable userSettings lib;
    })
    (import ../../system/security/sshd.nix {
      authorizedKeys = systemSettings.authorizedKeys;
      inherit userSettings systemSettings lib;
    })
  ]
  ++ lib.optional (systemSettings.systemBasicToolsEnable or false) ../../system/packages/system-basic-tools.nix
  ++ lib.optional (systemSettings.systemNetworkToolsEnable or false) ../../system/packages/system-network-tools.nix;

  wsl = {
    enable = true;
    defaultUser = userSettings.username;
    startMenuLaunchers = false;
    interop.includePath = true; # explorer.exe, wt.exe, clip.exe from the shell
    wslConf = {
      network.hostname = systemSettings.hostname;
      network.generateHosts = true;
      # false: NixOS owns /etc/resolv.conf. Neither WSL's own generator nor the
      # dnsTunneling proxy serve the Tailscale MagicDNS zone, so short names
      # ("vps-prod", "nas-aku") never resolve and ~/.ssh/config breaks.
      # See networking.nameservers below.
      network.generateResolvConf = false;
      # metadata: Linux permissions on /mnt/c (needed for ~/.ssh-style perms inside the Nextcloud tree)
      automount.options = "metadata,uid=1000,gid=100,umask=022,fmask=011,case=off";
      automount.root = "/mnt";
    };
  };

  # ~/Nextcloud = the Windows Nextcloud folder. A BIND mount, not a symlink:
  # Claude Code keys projects/<key> by getcwd(), which resolves symlinks — with a
  # symlink the Journal project would land under -mnt-c-Users-... and lose its memory.
  fileSystems."${home}/Nextcloud" = lib.mkIf (winUser != "") {
    device = "/mnt/c/Users/${winUser}/Nextcloud";
    fsType = "none";
    options = [ "bind" "nofail" "x-systemd.requires-mounts-for=/mnt/c" ];
  };

  # VS Code Remote-WSL, npx binaries and other prebuilt ELF need a loader path
  programs.nix-ld.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" userSettings.username ];
  nix.nixPath = [ "nixpkgs=flake:nixpkgs" ];
  nixpkgs.config.allowUnfree = true;

  networking.hostName = systemSettings.hostname;
  networking.firewall.enable = systemSettings.firewall;

  # DNS. Measured from inside WSL: 100.100.100.100 (MagicDNS, served by the
  # Windows Tailscale client and reachable because networkingMode=mirrored)
  # answers BOTH the tailnet zone and public names, while 192.168.8.1 and
  # 100.64.0.7 answer only public ones. The LAN resolver stays as the fallback
  # for when the Windows client is logged out. Short names need the search
  # domain: without it "vps-prod" returns empty and `ssh vps` fails.
  networking.nameservers = systemSettings.nameServers;
  networking.search = systemSettings.dnsSearchDomains or [ ];

  time.timeZone = systemSettings.timezone;
  i18n.defaultLocale = systemSettings.locale;
  i18n.extraLocaleSettings.LC_TIME = systemSettings.timeLocale;

  users.users.${userSettings.username} = {
    isNormalUser = true;
    description = userSettings.name;
    extraGroups = userSettings.extraGroups;
    uid = 1000;
    shell = pkgs.zsh;
  };
  environment.shells = [ pkgs.zsh ];
  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [ git wget curl home-manager wslu ]; # wslu: wslview opens URLs in the Windows browser

  environment.sessionVariables = {
    BROWSER = "wslview"; # links from the terminal open in Zen on Windows
    SERVER_ENV = systemSettings.serverEnv or "DEV";
  };

  system.stateVersion = systemSettings.systemStateVersion;
}
