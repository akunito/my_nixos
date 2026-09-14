# DESK_W11 — NixOS-WSL inside Windows 11 on the DESK box (dual boot).
# Flag sheet only; the module set is profiles/wsl/{configuration,home}.nix.
# Windows owns the desktop, GPU, browser, Nextcloud client and Tailscale
# (WSL runs in mirrored networking mode and rides the Windows tunnel).
# Runbook: docs/akunito/infrastructure/desk-w11-wsl.md
let
  secrets = import ../secrets/domains.nix;
in
{
  useRustOverlay = false;

  systemSettings = {
    hostname = "nixosw11aku";
    profile = "wsl";
    envProfile = "DESK_W11"; # Claude Code + claude-sync machine identity
    # -h: NixOS-WSL brings its own hardware config; install.sh must not regenerate one.
    # -d: docker is native inside WSL, never stop it for a rebuild.
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_W11 -s -h -d";
    bootMode = "bios"; # unused: NixOS-WSL disables the boot loader
    grubDevice = "/dev/";
    gpuType = "none"; # no GPU passthrough needed (no local LLM on W11)
    kernelModules = [ ];
    systemStable = true; # same base channel as DESK (nixos-25.11)

    # === WSL ===
    wslWindowsUser = "diego"; # the Windows account on WINAKU -> C:\Users\diego, /mnt/c/Users/diego
    gpgPinentryCurses = true; # terminal pinentry, no Qt

    # === Security ===
    fuseAllowOther = false;
    doasEnable = false;
    wrappSudoToDoas = false;
    sudoNOPASSWD = false;
    sudoAskpassEnable = false; # no GUI askpass
    pkiCertificates = [ ];
    firewall = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    sshPort = 22; # mirrored networking exposes it on the LAN; keys only
    authorizedKeys = [ # who may ssh INTO WSL (keys only)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # === Network ===
    networkManager = false; # WSL manages the interface
    resolvedEnable = false; # NixOS writes /etc/resolv.conf (generateResolvConf = false)
    # 100.100.100.100 is the Windows Tailscale client's MagicDNS resolver; mirrored
    # networking makes it reachable from WSL. It resolves the tailnet zone AND
    # forwards public names. 192.168.8.1 is the fallback for a logged-out client.
    nameServers = [ "100.100.100.100" "192.168.8.1" ];
    dnsSearchDomains = [ "tailnet.headscale.akunito.com" ]; # so `ssh vps` (HostName vps-prod) resolves
    wifiPowerSave = false;
    tailscaleEnable = false; # Windows client + mirrored networking instead
    wireguardEnable = false;

    # === NAS (same three NFS mounts as DESK) ===
    nfsClientEnable = true;
    nfsMounts = [
      {
        what = "192.168.20.200:/mnt/ssdpool/media";
        where = "/mnt/NFS_media";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,soft,retrans=3,timeo=50";
      }
      {
        what = "192.168.20.200:/mnt/ssdpool/workstation_backups";
        where = "/mnt/NFS_Backups";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,soft,retrans=3,timeo=50";
      }
      {
        what = "192.168.20.200:/mnt/extpool/downloads";
        where = "/mnt/NFS_downloads";
        type = "nfs";
        options = "noatime,rsize=1048576,wsize=1048576,nfsvers=4.2,tcp,soft,retrans=3,timeo=50";
      }
    ];
    nfsAutoMounts = [
      { where = "/mnt/NFS_media"; automountConfig = { TimeoutIdleSec = "600"; }; }
      { where = "/mnt/NFS_Backups"; automountConfig = { TimeoutIdleSec = "600"; }; }
      { where = "/mnt/NFS_downloads"; automountConfig = { TimeoutIdleSec = "600"; }; }
    ];

    # === Hardware/desktop: everything off (Windows owns it) ===
    mount2ndDrives = false; # DATA / DATA_SATA3 are NTFS → /mnt/d, /mnt/e via WSL automount
    servicePrinting = false;
    networkPrinters = false;
    serviceScannerEnable = false;
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    hibernateEnable = false;
    stylixEnable = false;
    sddmEnable = false;
    greetdEnable = false;
    enableSwayForDESK = false;
    swayAppsEnable = false;
    sambaEnable = false;
    sunshineEnable = false;
    appImageEnable = false;
    gamemodeEnable = false;
    xboxControllerEnable = false;
    starCitizenModules = false;
    nfsServerEnable = false;
    nixBinaryCacheServeEnable = false;
    infraNotifyEnable = false;
    prometheusWorkstationExporterEnable = false;

    # === Software ===
    systemBasicToolsEnable = true; # vim, rsync, nfs-utils, restic, sshfs, python3…
    systemNetworkToolsEnable = true;
    developmentToolsEnable = false; # IDEs live on Windows (VS Code + Remote-WSL)
    claudeCodeEnable = true; # standalone Claude Code: CLI + settings + MCP + git-crypt + uv, no IDEs
    claudeSyncEnable = true; # memory/skills/sessions ↔ VPS hub, identity DESK_W11
    claudeBackupToNextcloudEnable = false; # DESK already does it
    nextcloudEnable = false; # Windows client; ~/Nextcloud is a bind mount of the Windows folder
    nextcloudSyncFolder = "/home/akunito/Nextcloud";
    atuinAutoSync = true;
    sshHostsManaged = true; # ~/.ssh/config: vps, truenas, pve…
    githubAccessToken = secrets.githubAccessToken or "";

    # === Claude Code MCP credentials (same set as DESK) ===
    perplexityApiKey = secrets.perplexityApiKey or "";
    jellyseerrApiKey = secrets.jellyseerrApiKey or "";
    jellyseerrUrl = "http://192.168.20.200:5055";
    planeApiToken = secrets.planeApiToken or "";
    planeApiUrl = secrets.planeApiUrl or "";
    planeWorkspaceSlug = secrets.planeWorkspaceSlug or "";
    grafanaMcpToken = secrets.grafanaMcpToken or "";
    grafanaMcpUrl = secrets.grafanaMcpUrl or "";
    n8nMcpApiKey = secrets.n8nMcpApiKey or "";
    n8nMcpUrl = secrets.n8nMcpUrl or "";
    jlOnboardAccessToken = secrets.jlOnboardAccessToken or "";
    dbClaudeReadonlyConnStr = secrets.dbClaudeReadonlyConnStr or "";

    # === Auto update: off, W11 is updated by hand ===
    autoSystemUpdate = false;
    autoUserUpdate = false;
  };

  userSettings = {
    username = "akunito";
    name = "akunito";
    email = "diego88aku@gmail.com";
    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";
    dotfilesDir = "/home/akunito/.dotfiles";
    theme = "ashes";
    wm = "none"; # not consumed by the wsl module set
    wmEnableHyprland = false;
    browser = "none";
    spawnBrowser = "none";
    term = "kitty"; # tmux/starship expectations; the real terminal is Windows Terminal
    font = "JetBrainsMono Nerd Font Mono";
    fontPkg = null;
    editor = "nano";
    extraGroups = [ "wheel" "docker" ];
    starshipHostStyle = "bold magenta"; # different colour than DESK's cyan: same box, other OS
    dockerEnable = true;
    virtualizationEnable = false;
    tmuxPersistenceEnable = true;
    userBasicPkgsEnable = false; # GUI bundle (Bitwarden, Obsidian, Spotify…) lives on Windows
    userAiPkgsEnable = false;
    openCodeEnable = false;
    zenBrowserEnable = false;
    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519
        AddKeysToAgent yes

      # VPS (Tailscale, via the Windows client in mirrored mode)
      Host vps vps-prod 100.64.0.6
        Port 56777
        ForwardAgent yes
    '';
  };
}
