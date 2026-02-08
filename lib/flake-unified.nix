# Unified Flake Builder
# Generates nixosConfigurations/darwinConfigurations for all profiles
# from a single flake.nix with all inputs as a superset
#
# Usage in flake.nix:
#   outputs = inputs@{ self, ... }:
#     let
#       mkUnified = import ./lib/flake-unified.nix;
#     in
#       mkUnified {
#         inherit inputs self;
#         profiles = {
#           DESK = ./profiles/DESK-config.nix;
#           LAPTOP_L15 = ./profiles/LAPTOP_L15-config.nix;
#           # ...
#         };
#       };

{ inputs, self, profiles }:

let
  lib = inputs.nixpkgs.lib;

  # Import flake-base.nix for building individual profile outputs
  mkProfile = import ./flake-base.nix;

  # Build outputs for a single profile
  # Returns: { nixosConfigurations.PROFILENAME = ...; homeConfigurations.PROFILENAME = ...; ... }
  buildProfile = name: configPath:
    let
      profileConfig = import configPath;
      baseOutputs = mkProfile { inherit inputs self profileConfig; };

      # Rename "system" -> profile name in nixosConfigurations
      nixosConfigs = if baseOutputs ? nixosConfigurations.system
        then { ${name} = baseOutputs.nixosConfigurations.system; }
        else {};

      # Rename "system" -> profile name in darwinConfigurations
      darwinConfigs = if baseOutputs ? darwinConfigurations.system
        then { ${name} = baseOutputs.darwinConfigurations.system; }
        else {};

      # Rename "user" -> profile name in homeConfigurations
      homeConfigs = if baseOutputs ? homeConfigurations.user
        then { ${name} = baseOutputs.homeConfigurations.user; }
        else {};
    in {
      nixosConfigurations = nixosConfigs;
      darwinConfigurations = darwinConfigs;
      homeConfigurations = homeConfigs;
    };

  # Build all profiles and merge their outputs
  allProfileOutputs = lib.mapAttrs buildProfile profiles;

  # Merge all nixosConfigurations from all profiles
  mergedNixosConfigurations = lib.foldl' (acc: profileOutputs:
    acc // profileOutputs.nixosConfigurations
  ) {} (lib.attrValues allProfileOutputs);

  # Merge all darwinConfigurations from all profiles
  mergedDarwinConfigurations = lib.foldl' (acc: profileOutputs:
    acc // profileOutputs.darwinConfigurations
  ) {} (lib.attrValues allProfileOutputs);

  # Merge all homeConfigurations from all profiles
  mergedHomeConfigurations = lib.foldl' (acc: profileOutputs:
    acc // profileOutputs.homeConfigurations
  ) {} (lib.attrValues allProfileOutputs);

  # Read active profile for backward compatibility with #system alias
  # Falls back to "DESK" if .active-profile doesn't exist
  activeProfileFile = self + "/.active-profile";
  activeProfile =
    if builtins.pathExists activeProfileFile
    then lib.strings.trim (builtins.readFile activeProfileFile)
    else "DESK";  # Default fallback

  # Add "system" alias pointing to active profile (backward compat)
  nixosConfigsWithAlias = mergedNixosConfigurations // (
    if mergedNixosConfigurations ? ${activeProfile}
    then { system = mergedNixosConfigurations.${activeProfile}; }
    else {}
  );

  darwinConfigsWithAlias = mergedDarwinConfigurations // (
    if mergedDarwinConfigurations ? ${activeProfile}
    then { system = mergedDarwinConfigurations.${activeProfile}; }
    else {}
  );

  homeConfigsWithAlias = mergedHomeConfigurations // (
    if mergedHomeConfigurations ? ${activeProfile}
    then { user = mergedHomeConfigurations.${activeProfile}; }
    else {}
  );

  # Systems that can run packages/apps
  supportedLinuxSystems = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];
  supportedDarwinSystems = [ "aarch64-darwin" "x86_64-darwin" ];
  supportedSystems = supportedLinuxSystems ++ supportedDarwinSystems;

  forAllSystems = lib.genAttrs supportedSystems;
  nixpkgsFor = forAllSystems (system: import inputs.nixpkgs { inherit system; });

in {
  # All NixOS configurations (DESK, LAPTOP_L15, LXC_monitoring, etc. + "system" alias)
  nixosConfigurations = nixosConfigsWithAlias;

  # All Darwin configurations (MACBOOK-KOMI, etc. + "system" alias)
  darwinConfigurations = darwinConfigsWithAlias;

  # All Home Manager configurations (DESK, LAPTOP_L15, etc. + "user" alias)
  homeConfigurations = homeConfigsWithAlias;

  # Packages (install script)
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
