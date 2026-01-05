# Default systemSettings and userSettings
# These are the common values shared across all profiles
# Profile-specific configs will override these values

{ pkgs, ... }:

{
  systemSettings = {
    # System architecture - most profiles use x86_64-linux
    system = "x86_64-linux";
    
    # Common defaults (profile-specific values will override)
    timezone = "Europe/Warsaw";
    locale = "en_US.UTF-8";
    bootMode = "uefi";
    bootMountPath = "/boot";
    grubDevice = "";
    
    # Kernel defaults
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = [ 
      "i2c-dev" 
      "i2c-piix4" 
    ];
    
    # Security defaults
    fuseAllowOther = false;
    doasEnable = false;
    sudoEnable = true;
    DOASnoPass = false;
    wrappSudoToDoas = false;
    sudoNOPASSWD = true;
    sudoCommands = [
      {
        command = "/run/current-system/sw/bin/systemctl suspend";
        options = [ "NOPASSWD" ];
      }
      {
        command = "/run/current-system/sw/bin/restic";
        options = [ "NOPASSWD" "SETENV" ];
      }
    ];
    pkiCertificates = [ ];
    
    # Polkit defaults
    polkitEnable = false;
    polkitRules = ''
      polkit.addRule(function(action, subject) {
        if (
          subject.isInGroup("users") && (
            // Allow running rsync and restic
            (action.id == "org.freedesktop.policykit.exec" &&
              (action.lookup("command") == "/run/current-system/sw/bin/rsync" ||
              action.lookup("command") == "/run/current-system/sw/bin/restic"))
          )
        ) {
          return polkit.Result.YES;
        }
      });
    '';
    
    # Backup defaults
    resticWrapper = true;
    rsyncWrapper = true;
    homeBackupEnable = false;
    homeBackupDescription = "Backup Home Directory with Restic";
    homeBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/personal_backup.sh";
    homeBackupUser = "akunito";
    homeBackupTimerDescription = "Timer for home_backup service";
    homeBackupOnCalendar = "0/6:00:00";
    homeBackupCallNextEnabled = false;
    homeBackupCallNext = [ "remote_backup.service" ];
    
    remoteBackupEnable = false;
    remoteBackupDescription = "Copy Restic Backup to Remote Server";
    remoteBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/personal_backup_remote.sh";
    remoteBackupUser = "akunito";
    remoteBackupTimerDescription = "Timer for remote_backup service";
    
    # Network defaults
    networkManager = true;
    defaultGateway = null;
    nameServers = [ "192.168.8.1" "192.168.8.1" ];
    wifiPowerSave = true;
    resolvedEnable = false;
    
    # Firewall defaults
    firewall = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    
    # Drive defaults
    mount2ndDrives = false;
    bootSSH = false;
    # Disk defaults - all disabled by default, profiles enable as needed
    disk1_enabled = false;
    disk1_name = "/mnt/2nd_NVME";
    disk1_device = "/dev/mapper/2nd_NVME";
    disk1_fsType = "ext4";
    disk1_options = [ "nofail" "x-systemd.device-timeout=3s" ];
    disk2_enabled = false;
    disk2_name = "/mnt/DATA_SATA3";
    disk2_device = "/dev/disk/by-uuid/B8AC28E3AC289E3E";
    disk2_fsType = "ntfs3";
    disk2_options = [ "nofail" "x-systemd.device-timeout=3s" ];
    disk3_enabled = false;
    disk3_name = "/mnt/NFS_media";
    disk3_device = "192.168.20.200:/mnt/hddpool/media";
    disk3_fsType = "nfs4";
    disk3_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    disk4_enabled = false;
    disk4_name = "/mnt/NFS_emulators";
    disk4_device = "192.168.20.200:/mnt/ssdpool/emulators";
    disk4_fsType = "nfs4";
    disk4_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    disk5_enabled = false;
    disk5_name = "/mnt/NFS_library";
    disk5_device = "192.168.20.200:/mnt/ssdpool/library";
    disk5_fsType = "nfs4";
    disk5_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    disk6_enabled = false;
    disk6_name = "/mnt/DATA";
    disk6_device = "/dev/disk/by-uuid/48B8BD48B8BD34F2";
    disk6_fsType = "ntfs3";
    disk6_options = [ "nofail" "x-systemd.device-timeout=3s" ];
    disk7_enabled = false;
    disk7_name = "/mnt/EXT";
    disk7_device = "/dev/disk/by-uuid/b6be2dd5-d6c0-4839-8656-cb9003347c93";
    disk7_fsType = "ext4";
    disk7_options = [ "nofail" "x-systemd.device-timeout=5s" ];
    
    # NFS defaults
    nfsServerEnable = false;
    nfsExports = ''
      /mnt/example   192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
      /mnt/example2  192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
    '';
    nfsClientEnable = false;
    nfsMounts = [ ];
    nfsAutoMounts = [ ];
    
    # SSH defaults
    authorizedKeys = [ ];
    hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];
    
    # Printer defaults
    servicePrinting = false;
    networkPrinters = false;
    sharePrinter = false;
    
    # Power management defaults
    iwlwifiDisablePowerSave = false;
    TLP_ENABLE = false;
    PROFILE_ON_BAT = "performance";
    PROFILE_ON_AC = "performance";
    WIFI_PWR_ON_AC = "off";
    WIFI_PWR_ON_BAT = "off";
    INTEL_GPU_MIN_FREQ_ON_AC = 300;
    INTEL_GPU_MIN_FREQ_ON_BAT = 300;
    LOGIND_ENABLE = false;
    lidSwitch = "ignore";
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    powerKey = "ignore";
    powerManagement_ENABLE = false;
    power-profiles-daemon_ENABLE = false;
    
    # Feature flags defaults
    starCitizenModules = false;
    vivaldiPatch = false;
    sambaEnable = false;
    sunshineEnable = false;
    wireguardEnable = false;
    stylixEnable = false;
    xboxControllerEnable = false;
    appImageEnable = false;
    
    # Font defaults - will be computed based on systemStable in flake-base.nix
    # This is just a placeholder
    fonts = [ ];
    
    # System defaults
    swapFileEnable = false;
    swapFileSyzeGB = 32;
    downloadBufferSize = "134217728";
    systemStateVersion = "24.11";
    systemStable = false;
    
    # Update defaults
    autoSystemUpdateEnable = true;
    autoSystemUpdateDescription = "Auto Update System service";
    autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoSystemUpdate.sh";
    autoSystemUpdateUser = "root";
    autoSystemUpdateTimerDescription = "Auto Update System timer";
    autoSystemUpdateOnCalendar = "06:00:00";
    autoSystemUpdateCallNext = [ "autoUserUpdate.service" ];
    
    autoUserUpdateEnable = true;
    autoUserUpdateDescription = "Auto User Update";
    autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoUserUpdate.sh";
    autoUserUpdateUser = "akunito";
    
    # System packages - empty by default, profiles specify their own
    systemPackages = [ ];
    
    # Background package - handled in flake-base.nix with proper self reference
    # Profiles can override this if needed
  };
  
  userSettings = {
    # User defaults
    email = "diego88aku@gmail.com";
    extraGroups = [ "networkmanager" "wheel" ];
    
    # Theme and WM defaults
    theme = "miramare";
    wm = "plasma6";
    wmType = "wayland"; # Will be computed from wm
    wmEnableHyprland = false;
    
    # Feature flags
    dockerEnable = true;
    virtualizationEnable = true;
    qemuGuestAddition = false;
    
    # Git defaults
    gitUser = "akunito";
    gitEmail = "diego88aku@gmail.com";
    
    # Application defaults
    browser = "vivaldi";
    spawnBrowser = "vivaldi";
    defaultRoamDir = "Personal.p";
    term = "kitty";
    font = "Intel One Mono";
    fontPkg = pkgs.intel-one-mono;
    editor = "nano";
    
    # Home packages - empty by default, profiles specify their own
    homePackages = [ ];
    
    # Tailscale
    tailscaleEnabled = false;
    
    # ZSH prompt defaults
    zshinitContent = ''
      PROMPT=" ◉ %U%F{magenta}%n%f%u@%U%F{magenta}%m%f%u:%F{yellow}%~%f
      %F{green}→%f "
      RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
      [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
    '';
    
    # SSH config defaults
    sshExtraConfig = ''
      # sshd.nix -> programs.ssh.extraConfig
      Host github.com
        HostName github.com
        User akunito
        IdentityFile ~/.ssh/id_ed25519 # Generate this key for github if needed
        AddKeysToAgent yes
    '';
    
    # Version
    homeStateVersion = "24.11";
    
    # Editor spawn command - computed from editor and term
    spawnEditor = "exec kitty -e nano"; # Will be computed
  };
}

