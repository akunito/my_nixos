{
  description = "Flake of Akunito NetLAB on x380";

  outputs = inputs@{ self, ... }:
    # NOTE that install.sh will replace the username and email by the active one by string replacement
    let
      # ---- SYSTEM SETTINGS ---- #
      systemSettings = {
        system = "x86_64-linux"; # system arch
        hostname = "netlab"; # hostname
        profile = "homelab"; # select a profile defined from my profiles directory
        timezone = "Europe/Warsaw"; # select timezone
        locale = "en_US.UTF-8"; # select locale
        bootMode = "uefi"; # uefi or bios
        bootMountPath = "/boot"; # mount path for efi boot partition; only used for uefi boot mode
        grubDevice = ""; # device identifier for grub; only used for legacy (bios) boot mode
        gpuType = "intel"; # amd, intel or nvidia; only makes some slight mods for amd at the moment
        
        # Security
        doasEnable = true; # for enabling doas
        sudoEnable = true; # for enabling sudo
        DOASnoPass = false; # for enabling doas without password
        wrappSudoToDoas = true; # for wrapping sudo with doas
        sudoNOPASSWD = false; # for allowing sudo without password (NOT Recommended, check sudo.md for more info)
        pkiCertificates = [ ];

        # Network
        networkManager = true;
        ipAddress = "192.168.0.100"; # ip to be reserved on router by mac (manually)
        wifiIpAddress = "192.168.0.101"; # ip to be reserved on router by mac (manually)
        defaultGateway = null; # default gateway
        nameServers = [ "8.8.8.8" "8.8.4.4" ]; # nameservers / DNS
        wifiPowerSave = false; # for enabling wifi power save for laptops

        # Firewall
        firewall = true;
        allowedTCPPorts = [ 52181 53 8093 ];
        allowedUDPPorts = [ 52181 53 8093 ];

        # LUKS drives
        bootSSH = true; # for enabling ssh on boot (to unlock encrypted drives by SSH)
        # check drives.nix & drives.org if you need to set your LUKS devices to be opened on boot and automate mounting.
        openLUKS = false; # drives.nix
        disk1_name = "DATA_4TB";
        disk1_path = "/dev/disk/by-uuid/231c229c-1daf-43b5-85d0-f1691fa3ab93";
        disk2_name = "TimeShift";
        disk2_path = "/dev/disk/by-uuid/04aaf88f-c0dd-40ad-be7e-85e29c0bd719";
        disk3_name = "Machines";
        disk3_path = "/dev/disk/by-uuid/452c53a6-0578-4c38-840d-87f1f3f34ddb";

        # SSH System settings for BOOT
        authorizedKeys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCfNRaYr4LSuhcXgI97o2cRfW0laPLXg7OzwiSIuV9N7cin0WC1rN1hYi6aSGAhK+Yu/bXQazTegVhQC+COpHE6oVI4fmEsWKfhC53DLNeniut1Zp02xLJppHT0TgI/I2mmBGVkEaExbOadzEayZVL5ryIaVw7Op92aTmCtZ6YJhRV0hU5MhNcW5kbUoayOxqWItDX6ARYQov6qHbfKtxlXAr623GpnqHeH8p9LDX7PJKycDzzlS5e44+S79JMciFPXqCtVgf2Qq9cG72cpuPqAjOSWH/fCgnmrrg6nSPk8rLWOkv4lSRIlZstxc9/Zv/R6JP/jGqER9A3B7/vDmE8e3nFANxc9WTX5TrBTxB4Od75kFsqqiyx9/zhFUGVrP1hJ7MeXwZJBXJIZxtS5phkuQ2qUId9zsCXDA7r0mpUNmSOfhsrTqvnr5O3LLms748rYkXOw8+M/bPBbmw76T40b3+ji2aVZ4p4PY4Zy55YJaROzOyH4GwUom+VzHsAIAJF/Tg1DpgKRklzNsYg9aWANTudE/J545ymv7l2tIRlJYYwYP7On/PC+q1r/Tfja7zAykb3tdUND1CVvSr6CkbFwZdQDyqSGLkybWYw6efVNgmF4yX9nGfOpfVk0hGbkd39lUQCIe3MzVw7U65guXw/ZwXpcS0k1KQ+0NvIo5Z1ahQ== akunito@Diegos-MacBook-Pro.local" ];
        hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" ];

        # Printer
        servicePrinting = false; 
        networkPrinters = false;
        sharePrinter = false; # for enabling printer sharing

        # Intel Network Adapter Power Management
        iwlwifiDisablePowerSave = true; # modify iwlwifi power save for Intel Adapter | true = disable power save | false = do nothing
        # TLP Power management
        TLP_ENABLE = true; # Disable for laptops if you want granular power management with profiles
        PROFILE_ON_AC = "performance";
        PROFILE_ON_BAT = "performance";
        WIFI_PWR_ON_AC = "off"; # Sets Wi-Fi power saving mode. off – disabled saving mode | on – enabled
        WIFI_PWR_ON_BAT = "off";
        INTEL_GPU_MIN_FREQ_ON_AC = 300; # sudo tlp-stat -g
        INTEL_GPU_MIN_FREQ_ON_BAT = 300;
        # logind settings
        LOGIND_ENABLE = true; # Disable for laptops if you want granular power management with profiles
        lidSwitch = "ignore"; # when the lid is closed, do one of "ignore", "poweroff", "reboot", "halt", "kexec", "suspend", "hibernate", "hybrid-sleep", "suspend-then-hibernate", "lock"
        lidSwitchExternalPower = "ignore"; # when the lid is closed but connected to power 
        lidSwitchDocked = "ignore"; # when the lid is closed, and connected to another display
        powerKey = "ignore";  # when pressing power key, do one of above
        # More Power settings
        powerManagement_ENABLE = false; # Enable power management profiles for desktop systems <<<
        power-profiles-daemon_ENABLE = false; # Enable power management profiles for desktop systems <<<

        # System packages
        systemPackages = with pkgs; [
          vim
          wget
          zsh
          git
          rclone
          rdiff-backup
          rsnapshot
          cryptsetup
          gocryptfs
          
          btop
          fzf
          # tldr
          atuin

          kitty # check if should be removed on labs
          home-manager
        ];

        # Remote Control
        sunshineEnable = false;
        # Wireguard
        wireguardEnable = false; 
        # Stylix
        stylixEnable = false;

        systemStateVersion = "24.05";

        # Auto update Settings
        autoUpdate = true; # for enabling automatic updates
        autoUpdate_dates = "20:00";
        autoUpdate_randomizedDelaySec = "45min";
        HomeAutoUpdate = false; # enable home manager auto update
        HomeAutoUpdate_frecuency = "weekly"; # enable home manager auto update
      };

      # ----- USER SETTINGS ----- #
      userSettings = rec {
        username = "akunito"; # username
        name = "akunito"; # name/identifier
        email = ""; # email (used for certain configurations)
        dotfilesDir = "/home/akunito/.dotfiles"; # absolute path of the local repo
        extraGroups = [ "networkmanager" "wheel" ];

        theme = "io"; # selcted theme from my themes directory (./themes/)
        wm = "plasma6"; # Selected window manager or desktop environment; must select one in both ./user/wm/ and ./system/wm/
        # window manager type (hyprland or x11) translator
        wmType = if (wm == "hyprland") then "wayland" else "x11";
        wmEnableHyprland = false; 

        dockerEnable = true; # for enabling docker
        virtualizationEnable = false; # for enabling virtualization
        qemuGuestAddition = false; # If the system is a QEMU VM

        gitUser = "akunito"; # git username
        gitEmail = "diego88aku@gmail.com"; # git email

        browser = "vivaldi"; # Default browser; must select one from ./user/app/browser/
        defaultRoamDir = "Personal.p"; # Default org roam directory relative to ~/Org
        term = "kitty"; # Default terminal command;
        font = "Intel One Mono"; # Selected font
        fontPkg = pkgs.intel-one-mono; # Font package

        # Home-Manager packages
        homePackages = with pkgs; [
          # Core
          zsh
          git
        ];
        tailscaleEnabled = false;
        
        homeStateVersion = "24.05";

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
          # patches = [ ./patches/emacs-no-version-check.patch ]; # DISABLING emacs patches??
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
                  # overlays = [ inputs.rust-overlay.overlays.default ]; # not needed
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
            ./system/bin/phoenix.nix
            inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x390
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
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-24.05";
    # emacs-pin-nixpkgs.url = "nixpkgs/f72123158996b8d4449de481897d855bc47c7bf6";
    # kdenlive-pin-nixpkgs.url = "nixpkgs/cfec6d9203a461d9d698d8a60ef003cac6d0da94";
    # nwg-dock-hyprland-pin-nixpkgs.url = "nixpkgs/2098d845d76f8a21ae4fe12ed7c7df49098d3f15";

    home-manager-unstable.url = "github:nix-community/home-manager/master";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-stable.url = "github:nix-community/home-manager/release-24.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master"; # additional settings for specific hardware

    # nix-on-droid = {
    #   url = "github:nix-community/nix-on-droid/master";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.home-manager.follows = "home-manager-unstable";
    # };

    # hyprland = {
    #   type = "git";
    #   url = "https://github.com/hyprwm/Hyprland";
    #   submodules = true;
    #   rev = "918d8340afd652b011b937d29d5eea0be08467f5";
    # };
    # hyprland.inputs.nixpkgs.follows = "nixpkgs";
    # hyprland-plugins.url = "github:hyprwm/hyprland-plugins/3ae670253a5a3ae1e3a3104fb732a8c990a31487";
    # hyprland-plugins.inputs.hyprland.follows = "hyprland";
    # hycov.url = "github:DreamMaoMao/hycov/de15cdd6bf2e46cbc69735307f340b57e2ce3dd0";
    # hycov.inputs.hyprland.follows = "hyprland";
    # hyprgrass.url = "github:horriblename/hyprgrass/736119f828eecaed2deaae1d6ff1f50d6dabaaba";
    # hyprgrass.inputs.hyprland.follows = "hyprland";

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
