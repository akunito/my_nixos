# Base flake module
# This contains the common flake structure that all profiles share
# It accepts profile-specific config and merges with defaults
# Supports both NixOS (Linux) and nix-darwin (macOS)

{ inputs, self, profileConfig, ... }:

let
  # Get lib first (needed for recursiveUpdate)
  # We'll determine which lib to use after checking systemStable
  lib-unstable = inputs.nixpkgs.lib;
  lib-stable = inputs.nixpkgs-stable.lib;

  # Import defaults - need to use a temporary pkgs for defaults
  tempPkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
  defaults = import ./defaults.nix { pkgs = tempPkgs; };

  # Merge defaults with profile config
  # Use recursiveUpdate for nested structures, but allow complete replacement of lists
  systemSettingsRaw = lib-unstable.recursiveUpdate defaults.systemSettings (profileConfig.systemSettings or {});
  userSettingsRaw = lib-unstable.recursiveUpdate defaults.userSettings (profileConfig.userSettings or {});

  # Detect OS type - "linux" for NixOS, "darwin" for macOS
  osType = systemSettingsRaw.osType or "linux";
  isDarwin = osType == "darwin";
  isLinux = !isDarwin;

  # Handle systemStable - check both systemSettings and userSettings (for HOME profile inconsistency)
  # Also check profile name for homelab/worklab
  systemStable = systemSettingsRaw.systemStable or userSettingsRaw.systemStable or
                 ((systemSettingsRaw.profile == "homelab") || (systemSettingsRaw.profile == "worklab"));

  # Now determine which lib to use
  lib = if systemStable then lib-stable else lib-unstable;

  # Re-merge with correct lib
  systemSettings = lib.recursiveUpdate defaults.systemSettings (profileConfig.systemSettings or {});
  userSettingsMerged = lib.recursiveUpdate defaults.userSettings (profileConfig.userSettings or {});

  # Get temporary pkgs for font computation
  tempPkgsStable = import inputs.nixpkgs-stable { system = systemSettings.system; };
  tempPkgsUnstable = import inputs.nixpkgs { system = systemSettings.system; };

  # Compute fonts based on systemStable (if not overridden in profile config)
  # Check if fonts were explicitly set in profile config
  fontsFromConfig = (profileConfig.systemSettings or {}).fonts or null;
  computedFonts = if fontsFromConfig != null
                  then fontsFromConfig
                  else if systemStable
                       then [
                         tempPkgsStable.nerd-fonts.jetbrains-mono
                         tempPkgsStable.nerd-fonts.symbols-only
                         tempPkgsStable.powerline
                       ]
                       else [
                         tempPkgsUnstable.nerd-fonts.jetbrains-mono
                         tempPkgsUnstable.nerd-fonts.symbols-only
                         tempPkgsUnstable.powerline
                       ];

  # Compute derived userSettings values first
  userSettings = userSettingsMerged // {
    # Compute wmType from wm (for darwin, default to "quartz" which is macOS native)
    wmType = if isDarwin then "quartz"
             else if ((userSettingsMerged.wm == "hyprland") || (userSettingsMerged.wm == "plasma") || (userSettingsMerged.wm == "plasma6") || (userSettingsMerged.wm == "sway"))
             then "wayland"
             else "x11";

    # Compute spawnEditor from editor and term
    spawnEditor = if (userSettingsMerged.editor == "emacsclient") then
                    "emacsclient -c -a 'emacs'"
                  else
                    (if ((userSettingsMerged.editor == "vim") ||
                         (userSettingsMerged.editor == "nvim") ||
                         (userSettingsMerged.editor == "nano")) then
                           "exec " + userSettingsMerged.term + " -e " + userSettingsMerged.editor
                     else
                       userSettingsMerged.editor);
  };

  # Evaluate package lists if they're functions (now that userSettings is defined)
  systemPackagesEvaluatedBase = if lib.isFunction (systemSettings.systemPackages or [])
                            then systemSettings.systemPackages pkgs pkgs-unstable
                            else systemSettings.systemPackages or [];

  homePackagesEvaluated = if lib.isFunction (userSettings.homePackages or [])
                          then userSettings.homePackages pkgs pkgs-unstable
                          else userSettings.homePackages or [];

  # Set fontPkg based on font name if not already set
  fontPkgMap = {
    "Intel One Mono" = pkgs.intel-one-mono;
    "JetBrainsMono Nerd Font" = pkgs.nerd-fonts.jetbrains-mono;
    "JetBrainsMono Nerd Font Mono" = pkgs.nerd-fonts.jetbrains-mono;
    # Add more font mappings as needed
  };
  userSettingsWithFontPkg = userSettings // {
    fontPkg = userSettings.fontPkg or fontPkgMap.${userSettings.font} or pkgs.intel-one-mono;
    homePackages = homePackagesEvaluated;
  };

  # Handle background-package if it references assets (Linux only)
  # If background-package is a path or needs self, we'll compute it here
  backgroundPackage = if isDarwin then null
                      else if systemSettings ? background-package && lib.isString systemSettings.background-package
                      then systemSettings.background-package
                      else if systemSettings ? background-package
                           then systemSettings.background-package
                           else pkgs.stdenvNoCC.mkDerivation {
                                name = "background-image";
                                src = self + "/assets/wallpapers";
                                dontUnpack = true;
                                installPhase = ''
                                  cp $src/fuji.jpg $out
                                '';
                              };

  # Add SDDM theme override if using plasma6 (which uses SDDM) - Linux only
  # This needs to be done after backgroundPackage is computed.
  #
  # SDDM theme configuration (controlled by feature flags)
  # - sddmForcePasswordFocus: Force password field focus (fixes multi-monitor focus issues)
  # - Keep the background image (Breeze "dark mode" via solid color was too aggressive)
  sddmThemeConfig = if isLinux && systemSettings.sddmForcePasswordFocus
    then ''
      [General]
      background = ${toString backgroundPackage}
      ForcePasswordFocus=true
    ''
    else if isLinux then ''
      [General]
      background = ${toString backgroundPackage}
    ''
    else "";

  systemPackagesEvaluated = systemPackagesEvaluatedBase ++
    lib.optional (isLinux && userSettings.wm == "plasma6") (
      pkgs.writeTextDir "share/sddm/themes/breeze-patched/theme.conf.user" sddmThemeConfig
    );

  systemSettingsWithFonts = systemSettings // {
    fonts = computedFonts;
    systemPackages = systemPackagesEvaluated;
    background-package = backgroundPackage;
  };

  # Create patched nixpkgs (Linux only - darwin doesn't need ROCm patches)
  # Note: Original code used systemSettings.gpu but field is actually gpuType
  nixpkgs-patched = if isDarwin then inputs.nixpkgs
    else (import inputs.nixpkgs {
      system = systemSettingsWithFonts.system;
      rocmSupport = (if (systemSettingsWithFonts.gpuType or "") == "amd" then true else false);
    }).applyPatches {
      name = "nixpkgs-patched";
      src = inputs.nixpkgs;
      patches = [
        # ./patches/emacs-no-version-check.patch
        # ./patches/nixpkgs-348697.patch
      ];
    };

  # Configure pkgs-stable
  pkgs-stable = import inputs.nixpkgs-stable {
    system = systemSettingsWithFonts.system;
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  # Configure pkgs-unstable
  # Check if rust-overlay should be used (from profile config or default to false)
  useRustOverlay = profileConfig.useRustOverlay or false;
  rustOverlay = if useRustOverlay && (inputs ? rust-overlay)
                then inputs.rust-overlay.overlays.default
                else (_: _: {});
  pkgs-unstable = import inputs.nixpkgs {
    system = systemSettingsWithFonts.system;
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
    overlays = lib.optional useRustOverlay rustOverlay;
  };

  # Configure pkgs based on systemStable and profile
  pkgs = if systemStable
         then
           pkgs-stable
         else if isDarwin
         then
           (import inputs.nixpkgs {
             system = systemSettingsWithFonts.system;
             config = {
               allowUnfree = true;
               allowUnfreePredicate = (_: true);
             };
             overlays = lib.optional useRustOverlay rustOverlay;
           })
         else
           (import nixpkgs-patched {
             system = systemSettingsWithFonts.system;
             config = {
               allowUnfree = true;
               allowUnfreePredicate = (_: true);
             };
             overlays = lib.optional useRustOverlay rustOverlay;
           });

  # Configure home-manager
  home-manager = if systemStable
                 then
                   inputs.home-manager-stable
                 else
                   inputs.home-manager-unstable;

  # Systems that can run tests (includes both Linux and Darwin)
  supportedLinuxSystems = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];
  supportedDarwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
  supportedSystems = supportedLinuxSystems ++ supportedDarwinSystems;

  # Function to generate a set based on supported systems
  forAllSystems = lib-unstable.genAttrs supportedSystems;
  forLinuxSystems = lib-unstable.genAttrs supportedLinuxSystems;

  # Attribute set of nixpkgs for each system
  nixpkgsFor = forAllSystems (system: import inputs.nixpkgs { inherit system; });

  # Darwin-specific configuration
  darwinConfiguration = if isDarwin && (inputs ? darwin) then {
    darwinConfigurations = {
      system = inputs.darwin.lib.darwinSystem {
        system = systemSettingsWithFonts.system;
        modules = [
          (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/configuration.nix")
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "before-hm";
            home-manager.extraSpecialArgs = {
              inherit pkgs-stable;
              inherit pkgs-unstable;
              systemSettings = systemSettingsWithFonts;
              userSettings = userSettingsWithFontPkg;
              inherit inputs;
            };
            home-manager.users.${userSettingsWithFontPkg.username} = import (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/home.nix");
          }
        ];
        specialArgs = {
          inherit pkgs-stable;
          inherit pkgs-unstable;
          systemSettings = systemSettingsWithFonts;
          userSettings = userSettingsWithFontPkg;
          inherit inputs;
        };
      };
    };
  } else {};

  # NixOS-specific configuration
  nixosConfiguration = if isLinux then {
    nixosConfigurations = {
      system = lib.nixosSystem {
        system = systemSettingsWithFonts.system;
        modules = [
          (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/configuration.nix")
          (self + "/system/bin/aku.nix")
        ];
        specialArgs = {
          inherit pkgs-stable;
          inherit pkgs-unstable;
          systemSettings = systemSettingsWithFonts;
          userSettings = userSettingsWithFontPkg;
          inherit inputs;
        };
      };
    };
  } else {};

  # Home configurations (always generated, but path differs slightly for darwin)
  homeConfiguration = {
    homeConfigurations = {
      user = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/home.nix")
        ];
        extraSpecialArgs = {
          inherit pkgs-stable;
          inherit pkgs-unstable;
          systemSettings = systemSettingsWithFonts;
          userSettings = userSettingsWithFontPkg;
          inherit inputs;
        };
      };
    };
  };

in
  # Merge all configurations
  homeConfiguration
  // nixosConfiguration
  // darwinConfiguration
  // {
    packages = forAllSystems (system:
      let pkgs = nixpkgsFor.${system};
      in {
        default = self.packages.${system}.install;

        install = pkgs.writeShellApplication {
          name = "install";
          runtimeInputs = with pkgs; [ git ];
          text = ''${self}/install.sh "$@"'';
        };
      });

    apps = forAllSystems (system: {
      default = self.apps.${system}.install;

      install = {
        type = "app";
        program = "${self.packages.${system}.install}/bin/install";
      };
    });
  }
