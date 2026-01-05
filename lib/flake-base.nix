# Base flake module
# This contains the common flake structure that all profiles share
# It accepts profile-specific config and merges with defaults

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
                         tempPkgsStable.nerdfonts
                         tempPkgsStable.powerline
                       ]
                       else [
                         tempPkgsUnstable.nerd-fonts.jetbrains-mono
                         tempPkgsUnstable.powerline
                       ];
  
  # Compute derived userSettings values first
  userSettings = userSettingsMerged // {
    # Compute wmType from wm
    wmType = if ((userSettingsMerged.wm == "hyprland") || (userSettingsMerged.wm == "plasma") || (userSettingsMerged.wm == "plasma6")) 
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
    # Add more font mappings as needed
  };
  userSettingsWithFontPkg = userSettings // {
    fontPkg = userSettings.fontPkg or fontPkgMap.${userSettings.font} or pkgs.intel-one-mono;
    homePackages = homePackagesEvaluated;
  };
  
  # Handle background-package if it references assets
  # If background-package is a path or needs self, we'll compute it here
  backgroundPackage = if systemSettings ? background-package && lib.isString systemSettings.background-package
                      then systemSettings.background-package
                      else if systemSettings ? background-package
                           then systemSettings.background-package
                           else pkgs.stdenvNoCC.mkDerivation {
                                name = "background-image";
                                src = self + "/assets/wallpapers";
                                dontUnpack = true;
                                installPhase = ''
                                  cp $src/lock8.png $out
                                '';
                              };
  
  # Add SDDM wallpaper override if using plasma6 (which uses SDDM)
  # This needs to be done after backgroundPackage is computed
  systemPackagesEvaluated = systemPackagesEvaluatedBase ++ lib.optional (userSettings.wm == "plasma6") (
    pkgs.writeTextDir "share/sddm/themes/breeze/theme.conf.user" ''
      [General]
      background = ${toString backgroundPackage}
      ForcePasswordFocus=true
    ''
  );
  
  systemSettingsWithFonts = systemSettings // {
    fonts = computedFonts;
    systemPackages = systemPackagesEvaluated;
    background-package = backgroundPackage;
  };
  
  # Create patched nixpkgs
  # Note: Original code used systemSettings.gpu but field is actually gpuType
  nixpkgs-patched =
    (import inputs.nixpkgs { 
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
  
  # Systems that can run tests
  supportedSystems = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];
  
  # Function to generate a set based on supported systems
  forAllSystems = lib-unstable.genAttrs supportedSystems;
  
  # Attribute set of nixpkgs for each system
  nixpkgsFor = forAllSystems (system: import inputs.nixpkgs { inherit system; });
  
in {
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
  
  nixosConfigurations = {
    system = lib.nixosSystem {
      system = systemSettingsWithFonts.system;
      modules = [
        (self + "/profiles" + ("/" + systemSettingsWithFonts.profile) + "/configuration.nix")
        (self + "/system/bin/phoenix.nix")
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

