# DESK_A Profile Configuration — Aga's desktop (hostname: nixosagadesk)
#
# Re-parented 2026-07-23: inherits LAPTOP-base.nix (NOT DESK-config.nix).
#   Why: DESK-config is akunito's Sway + homelab/dev rig and imports git-crypt
#   secrets (domains.nix + control-panel.nix). Aga's machines keep git-crypt
#   LOCKED, and DESK_A diverges from DESK on every major axis (Plasma6 vs Sway,
#   no dev/infra, different AMD hardware). Inheriting LAPTOP-base gives us the
#   shared "personal Plasma6 desktop software" baseline with NO secrets wired in
#   (secrets-free by construction, exactly like LAPTOP_A), then we swap the
#   laptop hardware/power flags for an AMD desktop and add DESK's full gaming
#   stack + a Brother printer.
#
# Hardware: AMD Ryzen 7 7800X3D + Radeon RX 9060 XT (Navi 44, RDNA4), amdgpu.

let
  base = import ./LAPTOP-base.nix;
  # Headscale domain is public — no git-crypt needed on this machine
  headscaleDomain = "headscale.akunito.com";
in
{
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    # ============================================================================
    # MACHINE IDENTITY
    # ============================================================================
    hostname = "nixosagadesk"; # renamed from "nixosaga" (LAPTOP_A is also nixosaga)
    profile = "personal"; # selects profiles/personal/configuration.nix (LAPTOP-base omits this)
    envProfile = "DESK_A"; # Claude Code context awareness
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_A -s -u";

    # ============================================================================
    # HARDWARE — AMD CPU + GPU desktop (override LAPTOP-base laptop hardware)
    # ============================================================================
    gpuType = "amd"; # RX 9060 XT — drives amdgpu/ROCm + gaming AMD wrappers (radv)
    amdgpuSuspendWorkaround = true; # RDNA4 SMU suspend regression (as on DESK's RX 9070 XT)
    kernelModules = [
      "xpadneo"      # Xbox controller
      "hid_nintendo" # Joy-Con controller
    ];

    # Network (informational fields; wired LAN, reserved by MAC on pfSense)
    ipAddress = "192.168.8.79";
    wifiIpAddress = "192.168.8.79";
    wifiPowerSave = false;   # desktop — override LAPTOP-base (true)
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    resolvedEnable = false;

    # ============================================================================
    # POWER — desktop, handed to Plasma 6 / PowerDevil (mirror LAPTOP_A)
    # ============================================================================
    # Override every laptop power/battery flag from LAPTOP-base. No TLP, no
    # battery thresholds, no lid/idle-on-battery logic — Plasma PowerDevil owns
    # energy management (Settings → Power Management).
    enableLaptopPerformance = false;   # override LAPTOP-base (true)
    TLP_ENABLE = false;                # override LAPTOP-base (true) — laptop-only
    power-profiles-daemon_ENABLE = true;  # drives Plasma power profiles
    powerManagement_ENABLE = true;     # REQUIRED for PowerDevil/upower Energy page
    powerKey = "ignore";               # override LAPTOP-base "suspend" (desktop)
    swaySmartLidEnable = false;         # no lid
    swayIdlePowerAwareEnable = false;   # Sway/laptop only
    swayBatteryReduceEffects = false;   # no battery
    hibernateEnable = false;            # no hibernate on this desktop
    laptopPowerTuningEnable = false;    # laptop idle power tuning
    bluetoothPowerOnBoot = true;        # desktop — radio on at boot (override LAPTOP-base false)

    # ============================================================================
    # DESKTOP ENVIRONMENT — Plasma 6 ONLY, no Sway/wlroots tooling
    # ============================================================================
    # LAPTOP-base ships a Sway environment (stylix/swww/waypaper/nwg/kanshi/
    # swaysome). DESK_A is Plasma 6 (userSettings.wm inherited "plasma6"), so
    # disable ALL of it — the user explicitly wants no Sway stuff (incl. stylix).
    enableSwayForDESK = false;
    stylixEnable = false;             # Plasma has its own theming
    swwwEnable = false;               # Sway wallpaper daemon
    waypaperEnable = false;           # Sway wallpaper GUI (broke HM under DESK)
    nwgDisplaysEnable = false;        # wlroots monitor GUI
    kanshiImperativeMode = false;     # wlroots monitor manager
    swaysomeNativeGroups = false;     # Sway workspace groups
    workspaceGroupsGuiEnable = false; # Sway workspace-groups GUI

    # ============================================================================
    # SECURITY / SUDO
    # ============================================================================
    fuseAllowOther = false;
    pkiCertificates = [ ];
    sudoAskpassEnable = true;              # GUI askpass when sudo has no TTY
    sudoTimestampTimeoutMinutes = 180;
    sshAgentSudoEnable = true;             # passwordless sudo over `ssh -A` (authorized key)
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # ============================================================================
    # PRINTING — Brother laser (brlaser driver)
    # ============================================================================
    servicePrinting = true;   # CUPS + brlaser + USB auto-enable
    networkPrinters = true;    # avahi/mDNS discovery
    serviceScannerEnable = false; # no scanner for now

    # ============================================================================
    # GAMING (system side) — full stack like DESK
    # ============================================================================
    gamemodeEnable = true;        # GameMode perf tuning (+ AMD split_lock_detect=off)
    xboxControllerEnable = true;  # xpadneo
    joycondEnable = true;         # Joy-Con daemon
    freesmLauncherEnable = true;  # FreeSM Launcher (Minecraft over Tailscale/AkuCraft)
    sunshineEnable = false;       # streaming off (stable pkg unreliable, as on LAPTOP_A)

    # ============================================================================
    # TAILSCALE / HEADSCALE (self-hosted) — desktop always on LAN
    # ============================================================================
    tailscaleEnable = true;
    tailscaleLoginServer = "https://${headscaleDomain}";
    tailscaleAcceptRoutes = false; # already on LAN — reach peers by tailscale IP
    tailscaleAcceptDns = false;    # keep pfSense DNS
    tailscaleLanAutoToggle = false;
    tailscaleGuiAutostart = true;  # autostart Trayscale in Plasma 6

    # ============================================================================
    # MONITORING
    # ============================================================================
    prometheusWorkstationExporterEnable = true; # update/disk/backup metrics
    allowedTCPPorts = [ 9100 ];                  # prometheus workstation exporter

    # ============================================================================
    # DEV / AI — off (not a dev machine; only audio transcription is kept, below)
    # ============================================================================
    developmentToolsEnable = false;
    aichatEnable = false;
    nixvimEnabled = false;
    lmstudioEnabled = false;
    voxtypeEnable = false; # Sway-keybind dictation — not on Plasma
    starCitizenModules = false;
    vivaldiPatch = false;

    # ============================================================================
    # CHANNEL — pin to stable 25.11 (user wants stable on DESK_A)
    # ============================================================================
    systemStable = true; # override LAPTOP-base (false)

    # ============================================================================
    # AUTO-UPDATE — weekly stable updates (mirrors LAPTOP_A / VPS / NAS)
    # ============================================================================
    autoSystemUpdateEnable = true;
    autoUserUpdateEnable = true;
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoSystemUpdate.sh";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/aga/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "aga";
    autoUserUpdateBranch = "release-25.11"; # HM channel matching stable system

    # System packages
    systemPackages = pkgs: pkgs-unstable: [
      pkgs.tldr
    ];

    # NOTE (deferred to a later step): workstation home backup to the NAS
    # (homeBackupEnable + NFS /mnt/NFS_Backups mount) — set up once the NAS
    # target is confirmed, mirroring LAPTOP_X13.
  };

  userSettings = base.userSettings // {
    # ============================================================================
    # USER IDENTITY
    # ============================================================================
    username = "aga";
    name = "aga";
    email = "diego88aku@gmail.com";
    dotfilesDir = "/home/aga/.dotfiles";
    # wm ("plasma6"), theme ("ashes"), browser (vivaldi), term (kitty),
    # fileManager (dolphin), font, git*, zshinitContent, sshExtraConfig — all
    # inherited from LAPTOP-base.

    dockerEnable = false;
    virtualizationEnable = true;
    qemuGuestAddition = false;

    # ============================================================================
    # PACKAGES
    # ============================================================================
    userBasicPkgsEnable = true;
    userAiPkgsEnable = false; # no big AI (lmstudio/ollama)
    homePackages = pkgs: pkgs-unstable: [
      pkgs.clinfo                     # OpenCL diagnostics
      pkgs.kdePackages.dolphin        # file manager
      pkgs-unstable.kdePackages.kcalc # calculator
    ];

    # ============================================================================
    # AUDIO TRANSCRIPTION — kept (whisper.cpp, Vulkan/AMD). CLI: meeting-record /
    # meeting-transcribe. This is the only "AI" the user wants on DESK_A.
    # ============================================================================
    meetingTranscribeEnable = true;

    # ============================================================================
    # GAMING (user side) — Steam + Proton + Lutris + Bottles + light games
    # ============================================================================
    gamesEnable = true;         # master gate
    gamesLightEnable = true;    # RetroArch, emulators, pegasus, light games
    protongamesEnable = true;   # Wine, Bottles, Lutris, Proton (AMD-wrapped)
    steamPackEnable = true;     # Steam (+ gamescope, mangohud)
    starcitizenEnable = false;
    GOGlauncherEnable = false;
    dolphinEmulatorPrimehackEnable = false;
    rpcs3Enable = false;
  };
}
