{
  description = "Flake for my VM Desktop";

  outputs = inputs@{ self, ... }:
    # NOTE that install.sh will replace the username and email by the active one by string replacement
    let
      # ---- SYSTEM SETTINGS ---- #
      systemSettings = {
        system = "x86_64-linux"; # system arch
        hostname = "nixosdesk"; # hostname
        profile = "personal"; # select a profile defined from my profiles directory
        timezone = "Europe/Warsaw"; # select timezone
        locale = "en_US.UTF-8"; # select locale
        bootMode = "uefi"; # uefi or bios
        bootMountPath = "/boot"; # mount path for efi boot partition; only used for uefi boot mode
        grubDevice = ""; # device identifier for grub; only used for legacy (bios) boot mode
        gpuType = "amd"; # amd, intel or nvidia; only makes some slight mods for amd at the moment
        amdLACTdriverEnable = false; # for enabling amdgpu lact driver

        kernelPackages = pkgs.linuxPackages_latest; # linuxPackages_xanmod_latest; # kernel packages to use
        
        kernelModules = [ 
          "i2c-dev" 
          "i2c-piix4" 
          "cpufreq_powersave" 
        ]; # kernel modules to load
        
        # Security
        doasEnable = false; # for enabling doas
        sudoEnable = true; # for enabling sudo
        DOASnoPass = false; # for enabling doas without password
        wrappSudoToDoas = false; # for wrapping sudo with doas
        sudoNOPASSWD = true; # for allowing sudo without password (NOT Recommended, check sudo.md for more info)
        sudoCommands = [
          {
            command = "/run/current-system/sw/bin/systemctl suspend"; # this requires polkit rules to be set
            options = [ "NOPASSWD" ];
          }
          {
            command = "/run/current-system/sw/bin/restic";
            options = [ "NOPASSWD" "SETENV" ];
          }
        ];
        pkiCertificates = [ ];
        # Polkit
        polkitEnable = true;
        polkitRules = ''
          polkit.addRule(function(action, subject) {
            if (
              subject.isInGroup("users") && (
                // Allow reboot and power-off actions
                action.id == "org.freedesktop.login1.reboot" ||
                action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
                action.id == "org.freedesktop.login1.power-off" ||
                action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
                action.id == "org.freedesktop.login1.suspend" ||
                action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
                action.id == "org.freedesktop.login1.logout" ||
                action.id == "org.freedesktop.login1.logout-multiple-sessions" ||

                // Allow managing specific systemd units
                (action.id == "org.freedesktop.systemd1.manage-units" &&
                  action.lookup("verb") == "start" &&
                  action.lookup("unit") == "mnt-NFS_Backups.mount") ||

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

        # Backups
        resticWrapper = true; # for enabling restic wrapper
        rsyncWrapper = true; # for enabling rsync wrapper

        homeBackupEnable = false; # restic.nix
        homeBackupDescription = "Backup Home Directory with Restic";
        homeBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/nixosdesk_backup.sh";
        homeBackupUser = "akunito";
        homeBackupTimerDescription = "Timer for home_backup service";
        homeBackupOnCalendar = "0/12:00:00"; # Every 12 hour
        homeBackupCallNextEnabled = true; # for calling next service after backup
        homeBackupCallNext = [ "remote_backup.service" ]; # service to call after backup

        remoteBackupEnable = false; # restic.nix
        remoteBackupDescription = "Copy Restic Backup to Remote Server";
        remoteBackupExecStart = "/run/current-system/sw/bin/sh /home/akunito/myScripts/nixosdesk_backup_remote.sh";
        remoteBackupUser = "akunito";
        remoteBackupTimerDescription = "Timer for remote_backup service";

        # Network
        networkManager = true;
        ipAddress = "192.168.8.89"; # ip to be reserved on router by mac (manually)
        wifiIpAddress = "192.168.8.89"; # ip to be reserved on router by mac (manually)
        defaultGateway = null; # default gateway
        nameServers = [ "192.168.8.1" "192.168.8.1" ]; # nameservers / DNS
        wifiPowerSave = true; # for enabling wifi power save for laptops

        resolvedEnable = false; # for enabling systemd-resolved

        # Firewall
        firewall = true;
        allowedTCPPorts = [ 
          47984 47989 47990 48010 # sunshine
        ];
        allowedUDPPorts = [ 
          47998 47999 48000 8000 8001 8002 8003 8004 8005 8006 8007 8008 8009 8010 # sunshine
          # 51820 # Wireguard
        ];

        # LUKS drives
        bootSSH = false; # for enabling ssh on boot (to unlock encrypted drives by SSH)
        # check drives.nix & drives.org if you need to set your LUKS devices to be opened on boot and automate mounting.
        openLUKS = false; # drives.nix
        disk1_name = "SAMPLE1";
        disk1_path = "/dev/disk/by-uuid/231c229c-SAMPLE1";
        disk2_name = "SAMPLE2";
        disk2_path = "/dev/disk/by-uuid/04aaf88f-SAMPLE2";
        disk3_name = "SAMPLE3";
        disk3_path = "/dev/disk/by-uuid/452c53a6-SAMPLE3";
        # NFS server settings
        nfsServerEnable = false;
        nfsExports = ''
          /mnt/example   192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
          /mnt/example2  192.168.8.90(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000) 192.168.8.91(rw,sync,insecure,all_squash,anonuid=1000,anongid=1000)
        '';
        # NFS client settings
        nfsClientEnable = false;
        nfsMounts = [
          {
            what = "192.168.20.200:/mnt/hddpool/media";
            where = "/mnt/NFS_media";
            type = "nfs";
            options = "noatime";
          }
          {
            what = "192.168.20.200:/mnt/ssdpool/library";
            where = "/mnt/NFS_library";
            type = "nfs";
            options = "noatime";
          }
          {
            what = "192.168.20.200:/mnt/ssdpool/emulators";
            where = "/mnt/NFS_emulators";
            type = "nfs";
            options = "noatime";
          }
        ];
        nfsAutoMounts = [
          {
            where = "/mnt/NFS_media";
            automountConfig = {
              TimeoutIdleSec = "600";
            };
          }
          {
            where = "/mnt/NFS_library";
            automountConfig = {
              TimeoutIdleSec = "600";
            };
          }
          {
            where = "/mnt/NFS_emulators";
            automountConfig = {
              TimeoutIdleSec = "600";
            };
          }
        ];

        # SSH System settings for BOOT
        authorizedKeys = [ 
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" 
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4U8/5LIOEY8OtJhIej2dqWvBQeYXIqVQc6/wD/aAon diego88aku@gmail.com" # Desktop
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPp/10TlSOte830j6ofuEQ21YKxFD34iiyY55yl6sW7V diego88aku@gmail.com" # Laptop
        ];

        hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];
        
        # Printer
        servicePrinting = true; 
        networkPrinters = true;
        sharePrinter = false; # for enabling printer sharing

        # Intel Network Adapter Power Management
        iwlwifiDisablePowerSave = false; # modify iwlwifi power save for Intel Adapter | true = disable power save | false = do nothing
        # TLP Power management
        TLP_ENABLE = false; # Disable for laptops if you want granular power management with profiles
        PROFILE_ON_BAT = "performance";
        PROFILE_ON_AC = "performance";
        WIFI_PWR_ON_AC = "off"; # Sets Wi-Fi power saving mode. off – disabled saving mode | on – enabled
        WIFI_PWR_ON_BAT = "off";
        INTEL_GPU_MIN_FREQ_ON_AC = 300; # sudo tlp-stat -g
        INTEL_GPU_MIN_FREQ_ON_BAT = 300;
        # logind settings
        LOGIND_ENABLE = false; # Disable for laptops if you want granular power management with profiles
        lidSwitch = "ignore"; # when the lid is closed, do one of "ignore", "poweroff", "reboot", "halt", "kexec", "suspend", "hibernate", "hybrid-sleep", "suspend-then-hibernate", "lock"
        lidSwitchExternalPower = "ignore"; # when the lid is closed but connected to power 
        lidSwitchDocked = "ignore"; # when the lid is closed, and connected to another display
        powerKey = "ignore";  # when pressing power key, do one of above
        # More Power settings
        powerManagement_ENABLE = true; # Enable power management profiles for desktop systems <<<
        power-profiles-daemon_ENABLE = true; # Enable power management profiles for desktop systems <<<

        # Source a background image to use by SDDM
        background-package = pkgs.stdenvNoCC.mkDerivation {
          name = "background-image";
          src = ./assets/wallpapers;
          dontUnpack = true;
          installPhase = ''
            cp $src/lock8.png $out
          '';
        };

        # System packages
        systemPackages = [
          pkgs.vim
          pkgs.wget
          pkgs.nmap # net tool for port scanning
          pkgs.zsh
          pkgs.git
          pkgs.cryptsetup
          pkgs.home-manager
          pkgs.dnsutils # for dig command
          pkgs.btop
          pkgs.fzf
          pkgs.rsync
          pkgs.restic
          pkgs.lm_sensors
          pkgs.sshfs
          # pkgs.pciutils # install if you need some commands like lspci
          
          pkgs.qt5.qtbase
          pkgs-unstable.sunshine

          # Overwrite the Wallpaper for SDDM
          (
            pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
              [General]
              background = ${systemSettings.background-package}
            ''
          )
        ];

        vivaldiPatch = false; # for enabling vivaldi patch

        # Remote Control
        sunshineEnable = true;
        # Wireguard
        wireguardEnable = true;
        # Stylix
        stylixEnable = false;

        # Nerd font package
        fonts = [
          pkgs.nerd-fonts.jetbrains-mono # "nerd-fonts-jetbrains-mono" # If unstable or new version | "nerdfonts" if old version
          pkgs.powerline
        ];

        # Swap file
        swapFileEnable = false;
        swapFileSyzeGB = 32; # 32GB

        # System Version
        systemStateVersion = "24.11";
        # System stable or unstable
        systemStable = false; # use stable or unstable nixpkgs; if false, use nixpkgs-unstable

        # UPDATES -------------------------------------
        # Auto update System Settings
        autoSystemUpdateEnable = true; # for enabling auto system updates
        autoSystemUpdateDescription = "Auto Update System service";
        autoSystemUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoSystemUpdate.sh";
        autoSystemUpdateUser = "root";
        autoSystemUpdateTimerDescription = "Auto Update System timer";
        autoSystemUpdateOnCalendar = "06:00:00"; # At 6h every day
        autoSystemUpdateCallNext = [ "autoUserUpdate.service" ]; # service to call after update

        # Auto update User Settings
        autoUserUpdateEnable = true; # for enabling auto system updates
        autoUserUpdateDescription = "Auto User Update";
        autoUserUpdateExecStart = "/run/current-system/sw/bin/sh /home/akunito/.dotfiles/autoUserUpdate.sh";
        autoUserUpdateUser = "akunito";
      };

      # ----- USER SETTINGS ----- #
      userSettings = rec {
        username = "akunito"; # username
        name = "akunito"; # name/identifier
        email = "diego88aku@gmail.com"; # email (used for certain configurations)
        dotfilesDir = "/home/akunito/.dotfiles"; # absolute path of the local repo
        extraGroups = [ "networkmanager" "wheel" "input" "dialout" ];

        theme = "io"; # selcted theme from my themes directory (./themes/)
        wm = "plasma6"; # Selected window manager or desktop environment; must select one in both ./user/wm/ and ./system/wm/
        # window manager type (hyprland or x11) translator
        wmType = if ((wm == "hyprland") || (wm == "plasma")) then "wayland" else "x11";
        wmEnableHyprland = false; 

        dockerEnable = false; # for enabling docker
        virtualizationEnable = true; # for enabling virtualization
        qemuGuestAddition = true; # If the system is a QEMU VM

        gitUser = "akunito"; # git username
        gitEmail = "diego88aku@gmail.com"; # git email

        browser = "vivaldi"; # Default browser; must select one from ./user/app/browser/
        spawnBrowser = "vivaldi";
        defaultRoamDir = "Personal.p"; # Default org roam directory relative to ~/Org
        term = "kitty"; # Default terminal command;
        font = "Intel One Mono"; # Selected font
        fontPkg = pkgs.intel-one-mono; # Font package

        # Home-Manager packages
        homePackages = [
          pkgs.zsh
          pkgs.kitty
          pkgs.git
          pkgs.syncthing

          # vivaldi # temporary moved to configuration.nix for issue with plasma 6
          # qt5.qtbase
          pkgs-unstable.ungoogled-chromium

          pkgs-unstable.vscode
          pkgs-unstable.obsidian
          pkgs-unstable.spotify
          pkgs-unstable.vlc
          pkgs-unstable.candy-icons
          pkgs.calibre
          
          pkgs-unstable.libreoffice
          pkgs-unstable.telegram-desktop

          pkgs-unstable.qbittorrent
          pkgs-unstable.nextcloud-client
          pkgs-unstable.wireguard-tools
        ];

        tailscaleEnabled = false;

        zshinitContent = ''
          PROMPT=" ◉ %U%F{cyan}%n%f%u@%U%F{cyan}%m%f%u:%F{yellow}%~%f
          %F{green}→%f "
          RPROMPT="%F{red}▂%f%F{yellow}▄%f%F{green}▆%f%F{cyan}█%f%F{blue}▆%f%F{magenta}▄%f%F{white}▂%f"
          [ $TERM = "dumb" ] && unsetopt zle && PS1='$ '
        '';
          # %F{color}: Sets the foreground color (e.g., cyan, yellow, green, blue).
          # %n: Displays the username.
          # %m: Displays the hostname.
          # %~: Displays the current directory.
          # %f: Resets the color to default.

        sshExtraConfig = ''
          # sshd.nix -> programs.ssh.extraConfig
          Host github.com
            HostName github.com
            User akunito
            IdentityFile ~/.ssh/ed25519_github # Generate this key for github if needed
            AddKeysToAgent yes
        '';

        homeStateVersion = "24.11";

        editor = "nano"; # Default editor;
        # editor spawning translator
        # generates a command that can be used to spawn editor inside a gui
        # EDITOR and TERM session variables must be set in home.nix or other module
        # I set the session variable SPAWNEDITOR to this in my home.nix for convenience
        spawnEditor = if (editor == "emacsclient") then
                        "emacsclient -c -a 'emacs'"
                      else
                        (if ((editor == "vim") ||
                             (editor == "nvim") ||
                             (editor == "nano")) then
                               "exec " + term + " -e " + editor
                         else
                           editor);
      };

      # create patched nixpkgs
      nixpkgs-patched =
        (import inputs.nixpkgs { system = systemSettings.system; rocmSupport = (if systemSettings.gpu == "amd" then true else false); }).applyPatches {
          name = "nixpkgs-patched";
          src = inputs.nixpkgs;
          patches = [ #./patches/emacs-no-version-check.patch
                      #./patches/nixpkgs-348697.patch
                    ];
        };

      # configure pkgs
      # use nixpkgs if running a server (homelab or worklab profile)
      # otherwise use patched nixos-unstable nixpkgs
      pkgs = (if ((systemSettings.profile == "homelab") || (systemSettings.profile == "worklab"))
              then
                pkgs-stable
              else
                (import nixpkgs-patched {
                  system = systemSettings.system;
                  config = {
                    allowUnfree = true;
                    allowUnfreePredicate = (_: true);
                  };
                  # overlays = [ inputs.rust-overlay.overlays.default ];
                }));

      pkgs-stable = import inputs.nixpkgs-stable {
        system = systemSettings.system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
      };

      pkgs-unstable = import inputs.nixpkgs { 
        system = systemSettings.system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
        # overlays = [ inputs.rust-overlay.overlays.default ];
      };

      # pkgs-emacs = import inputs.emacs-pin-nixpkgs {
      #   system = systemSettings.system;
      # };

      # pkgs-kdenlive = import inputs.kdenlive-pin-nixpkgs {
      #   system = systemSettings.system;
      # };

      # pkgs-nwg-dock-hyprland = import inputs.nwg-dock-hyprland-pin-nixpkgs {
      #   system = systemSettings.system;
      # };

      # configure lib
      # use nixpkgs if running a server (homelab or worklab profile)
      # otherwise use patched nixos-unstable nixpkgs
      lib = (if ((systemSettings.profile == "homelab") || (systemSettings.profile == "worklab"))
             then
               inputs.nixpkgs-stable.lib
             else
               inputs.nixpkgs.lib);

      # use home-manager-stable if running a server (homelab or worklab profile)
      # otherwise use home-manager-unstable
      home-manager = (if ((systemSettings.profile == "homelab") || (systemSettings.profile == "worklab"))
             then
               inputs.home-manager-stable
             else
               inputs.home-manager-unstable);
      # home-manager = inputs.home-manager-stable; # Overriding home-manager logic to force stable

      # Systems that can run tests:
      supportedSystems = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];

      # Function to generate a set based on supported systems:
      forAllSystems = inputs.nixpkgs.lib.genAttrs supportedSystems;

      # Attribute set of nixpkgs for each system:
      nixpkgsFor =
        forAllSystems (system: import inputs.nixpkgs { inherit system; });

    in {
      homeConfigurations = {
        # Home Manager configuration for the main 
        user = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            (./. + "/profiles" + ("/" + systemSettings.profile) + "/home.nix") # load home.nix from selected PROFILE
          ];
          extraSpecialArgs = {
            # pass config variables from above
            inherit pkgs-stable;
            # inherit pkgs-emacs;
            # inherit pkgs-kdenlive;
            # inherit pkgs-nwg-dock-hyprland;
            inherit systemSettings;
            inherit userSettings;
            inherit inputs;
          };
        };
      };
      nixosConfigurations = {
        system = lib.nixosSystem {
          system = systemSettings.system;
          modules = [
            (./. + "/profiles" + ("/" + systemSettings.profile) + "/configuration.nix")
            # inputs.lix-module.nixosModules.default
            ./system/bin/phoenix.nix
            # inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t590
          ]; # load configuration.nix from selected PROFILE
          specialArgs = {
            # pass config variables from above
            inherit pkgs-stable;
            inherit systemSettings;
            inherit userSettings;
            inherit inputs;
          };
        };
      };
      # nixOnDroidConfigurations = {
      #   inherit pkgs;
      #   default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
      #     modules = [ ./profiles/nix-on-droid/configuration.nix ];
      #   };
      #   extraSpecialArgs = {
      #     # pass config variables from above
      #     inherit pkgs-stable;
      #     # inherit pkgs-emacs;
      #     inherit systemSettings;
      #     inherit userSettings;
      #     inherit inputs;
      #   };
      # };

      packages = forAllSystems (system:
        let pkgs = nixpkgsFor.${system};
        in {
          default = self.packages.${system}.install;

          install = pkgs.writeShellApplication {
            name = "install";
            runtimeInputs = with pkgs; [ git ]; # I could make this fancier by adding other deps
            text = ''${./install.sh} "$@"'';
          };
        });

      apps = forAllSystems (system: {
        default = self.apps.${system}.install;

        install = {
          type = "app";
          program = "${self.packages.${system}.install}/bin/install";
        };
      });
    };

  inputs = {
    # lix-module = {
    #   url = "https://git.lix.systems/lix-project/nixos-module/archive/2.90.0.tar.gz";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-24.11";
    # emacs-pin-nixpkgs.url = "nixpkgs/f72123158996b8d4449de481897d855bc47c7bf6";
    # kdenlive-pin-nixpkgs.url = "nixpkgs/cfec6d9203a461d9d698d8a60ef003cac6d0da94";
    # nwg-dock-hyprland-pin-nixpkgs.url = "nixpkgs/2098d845d76f8a21ae4fe12ed7c7df49098d3f15";

    home-manager-unstable.url = "github:nix-community/home-manager/master";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-stable.url = "github:nix-community/home-manager/release-24.11";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # nixos-hardware.url = "github:NixOS/nixos-hardware/master"; # additional settings for specific hardware

    # nix-on-droid = {
    #   url = "github:nix-community/nix-on-droid/master";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.home-manager.follows = "home-manager-unstable";
    # };

  #  hyprland = {
  #     url = "github:hyprwm/Hyprland/main?submodules=true";
  #     # url = "github:hyprwm/Hyprland/v0.47.2-b?submodules=true";
  #     inputs.nixpkgs.follows = "nixpkgs";
  #   };
  #   hyprland-plugins = {
  #     type = "git";
  #     url = "https://code.hyprland.org/hyprwm/hyprland-plugins.git";
  #     # rev = "4d7f0b5d8b952f31f7d2e29af22ab0a55ca5c219"; #v0.44.1
  #     inputs.hyprland.follows = "hyprland";
  #   };
  #   hyprlock = {
  #     type = "git";
  #     url = "https://code.hyprland.org/hyprwm/hyprlock.git";
  #     # rev = "73b0fc26c0e2f6f82f9d9f5b02e660a958902763";
  #     inputs.nixpkgs.follows = "nixpkgs";
  #   };
  #   hyprgrass.url = "github:horriblename/hyprgrass/427690aec574fec75f5b7b800ac4a0b4c8e4b1d5";
  #   hyprgrass.inputs.hyprland.follows = "hyprland";

    # nix-doom-emacs.url = "github:nix-community/nix-doom-emacs";
    # nix-doom-emacs.inputs.nixpkgs.follows = "emacs-pin-nixpkgs";

    # nix-straight.url = "github:librephoenix/nix-straight.el/pgtk-patch";
    # nix-straight.flake = false;
    # nix-doom-emacs.inputs.nix-straight.follows = "nix-straight";

    # eaf = {
    #   url = "github:emacs-eaf/emacs-application-framework";
    #   flake = false;
    # };
    # eaf-browser = {
    #   url = "github:emacs-eaf/eaf-browser";
    #   flake = false;
    # };
    # org-nursery = {
    #   url = "github:chrisbarrett/nursery";
    #   flake = false;
    # };
    # org-yaap = {
    #   url = "gitlab:tygrdev/org-yaap";
    #   flake = false;
    # };
    # org-side-tree = {
    #   url = "github:localauthor/org-side-tree";
    #   flake = false;
    # };
    # org-timeblock = {
    #   url = "github:ichernyshovvv/org-timeblock";
    #   flake = false;
    # };
    # org-krita = {
    #   url = "github:librephoenix/org-krita";
    #   flake = false;
    # };
    # org-xournalpp = {
    #   url = "gitlab:vherrmann/org-xournalpp";
    #   flake = false;
    # };
    # org-sliced-images = {
    #   url = "github:jcfk/org-sliced-images";
    #   flake = false;
    # };
    # magit-file-icons = {
    #   url = "github:librephoenix/magit-file-icons/abstract-icon-getters-compat";
    #   flake = false;
    # };
    # phscroll = {
    #   url = "github:misohena/phscroll";
    #   flake = false;
    # };
    # mini-frame = {
    #   url = "github:muffinmad/emacs-mini-frame";
    #   flake = false;
    # };

    # stylix.url = "github:danth/stylix";

    # rust-overlay.url = "github:oxalica/rust-overlay";

    blocklist-hosts = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };
  };
}
