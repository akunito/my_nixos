# DESK_A_DEV — unattended dev/test box for winsub (hostname: nixosakudev)
#
# Derived from DESK-config.nix (Diego's Sway rig: the same compositor stack the
# winsub work targets) and TRIMMED: no homelab services, no backups, no media/AI
# desktop extras, no games. It lives on its own drive + ESP in the DESK_A box
# (Aga's Plasma install and an optional Windows stay on their own drives).
#
# SECRETS-FREE BY CONSTRUCTION: git-crypt stays LOCKED on this box. DESK-config
# binds `secrets = import ../secrets/domains.nix` lazily, so importing it is
# harmless as long as EVERY attribute that reads `secrets.*` is overridden here
# (they all are, see "secret-derived attributes" below). Guard: install.sh on a
# locked checkout must keep evaluating; the eval test in winsub's plan
# (docs/plans/implementation-plan.md 0.1) copies the tree with domains.nix
# replaced by the template and evaluates this profile.
#
# Hardware: AMD Ryzen 7 7800X3D + Radeon RX 9060 XT (Navi 44, RDNA4), amdgpu.
# Driven over SSH (Tailscale) from DESK; keyboard/mouse by a Pico 2 H, screen by
# the Elgato 4K X on DESK; watchdog + BootOrder re-assert via system/hardware/devbox.nix.

let
  base = import ./DESK-config.nix;
  headscaleDomain = "headscale.akunito.com"; # public — no git-crypt needed here
in
{
  useRustOverlay = false;

  systemSettings = base.systemSettings // {
    # ---- identity -----------------------------------------------------------
    hostname = "nixosakudev"; # must differ from nixosagadesk (Headscale node name)
    envProfile = "DESK_A_DEV";
    installCommand = "$HOME/.dotfiles/install.sh $HOME/.dotfiles DESK_A_DEV -s -u";

    # ---- hardware (DESK_A box) ---------------------------------------------
    gpuType = "amd";
    amdLACTdriverEnable = false;          # no fan/OC control needed on the dev box
    amdgpuSuspendWorkaround = true;        # RDNA4 SMU suspend regression
    amdgpuDisableIps = false;              # DESK-specific DMCUB issue, not reproduced here
    gpuMemSamplerEnable = false;
    vramSamplerEnable = false;
    kernelModules = [ ];                   # no controllers on the dev box
    btrfsAutoScrubEnable = false;          # filesystem chosen at install time
    hibernateEnable = false;
    joycondEnable = false;
    xboxControllerEnable = false;
    webcamControlsEnable = false;
    rgbOffOpenrgbArgs = [ ];
    pkiCertificates = [ ];               # DESK-only local CA files

    # ---- unattended dev box (system/hardware/devbox.nix) --------------------
    devBoxEnable = true;
    devBoxAutoLoginUser = "akunito";      # greetd -> Sway without a password
    devBoxEspPartUuid = null;              # set after install: PARTUUID of this drive's ESP
    greetdEnable = true;
    sddmEnable = false;
    sudoAskpassEnable = false;             # nobody at the keyboard
    sudoTimestampTimeoutMinutes = 180;
    sshAgentSudoEnable = true;             # passwordless sudo over `ssh -A` (install.sh from DESK)
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAwUXqQXLaKW/WjsZ95fjHKU7sIhNEeqW685TbsrePiK diego88aku@gmail.com" # Laptop (X13)
    ];

    # ---- network: single NIC, pfSense reservation by MAC (same MAC as DESK_A) -
    networkBondingEnable = false;
    networkBondingVlans = [ ];
    ipAddress = "192.168.8.79";
    wifiIpAddress = "192.168.8.79";
    wifiPowerSave = false;
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    resolvedEnable = false;
    wolEnable = false;                     # enable once the NIC name is known (needs Ethernet)
    wireguardEnable = false;
    tailscaleEnable = true;
    trayscaleGuiEnable = true;
    tailscaleLoginServer = "https://${headscaleDomain}";
    tailscaleAcceptRoutes = false;
    tailscaleAcceptDns = false;

    # ---- homelab / services: OFF ------------------------------------------
    nextcloudEnable = false;
    goaCalendarEnable = false;
    claudeBackupToNextcloudEnable = false;
    nixBinaryCacheServeEnable = false;
    homeBackupEnable = false;
    nfsBackupEnable = false;
    nfsServerEnable = false;
    nfsClientEnable = false;
    ollamaServerEnable = false;
    llamaServerEnable = false;
    dockerRootlessKrunEnable = false;
    reaSandboxEnable = false;
    sunshineEnable = false;
    aion2MeterDaemonEnable = false;
    captureHubEnable = false;              # the Elgato is on DESK, not here
    freesmLauncherEnable = false;
    prometheusWorkstationExporterEnable = false;
    claudeSyncEnable = false;              # Claude drives this box from DESK; no memory sync here
    nasAiWidgetEnable = false;
    lmstudioEnabled = false;
    voxtypeEnable = false;
    dbCredentialsEnable = false;
    dbCredentialsPostgres = [ ];
    infraNotifyEnable = true;              # relay mode (secrets-free), like DESK_A
    infraNodeName = "desk-a-dev";
    infraBotUrl = "http://100.64.0.6:8765";
    developmentToolsEnable = true;
    gamemodeEnable = false;

    # ---- secret-derived attributes of DESK-config: every one overridden ------
    githubAccessToken = "";
    jellyseerrApiKey = "";
    planeApiToken = "";
    planeApiUrl = "";
    grafanaMcpToken = "";
    grafanaMcpUrl = "";
    dbClaudeReadonlyConnStr = "";
    n8nMcpApiKey = "";
    n8nMcpUrl = "";
    jlOnboardAccessToken = "";
    grafanaTelegramBotToken = "";
    grafanaTelegramChatId = "";
    infraTelegramDeploysThreadId = "";
  };

  userSettings = base.userSettings // {
    dockerRootlessEnable = true;           # rootless docker stays (builds in docker run --rm)
    virtualizationEnable = true;           # virt-manager/virtiofsd/virtio-win; QEMU itself comes from winsub's flake
    spotifyUrlHandlerEnable = false;
    userAiPkgsEnable = false;
    openCodeEnable = false;
    userMediaRecordingEnable = false;
    userGamedevPkgsEnable = false;
    meetingTranscribeEnable = false;
    zenBrowserEnable = false;
    zenSineEnable = false;
    zenIsDefaultBrowser = false;
    gamesEnable = false;
    gamesLightEnable = false;
    protongamesEnable = false;
    starcitizenEnable = false;
    GOGlauncherEnable = false;
    steamPackEnable = false;
    vkbasaltEnable = false;
    dolphinEmulatorPrimehackEnable = false;
    rpcs3Enable = false;
  };
}
