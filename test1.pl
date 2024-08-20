{
  # Define home configurations for multiple users
  homeConfigurations = {
    # Home Manager configuration for the main user
    user = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        (./. + "/profiles" + ("/" + systemSettings.profile) + "/home.nix")
      ];
      extraSpecialArgs = {
        inherit pkgs-stable;
        inherit systemSettings;
        inherit userSettings;
        inherit inputs;
      };
    };

    # Home Manager configuration for the new SSH user
    newuser = home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        (./. + "/profiles" + ("/" + systemSettings.profile) + "/newuser-home.nix")
      ];
      extraSpecialArgs = {
        inherit pkgs-stable;
        inherit systemSettings;
        # If needed, you can customize settings per user
        newUserSettings = {
          # Add specific settings for `newuser` here
        };
      };
    };
  };

  nixosConfigurations = {
    system = lib.nixosSystem {
      system = systemSettings.system;
      modules = [
        (./. + "/profiles" + ("/" + systemSettings.profile) + "/configuration.nix")
        ./system/bin/phoenix.nix
      ];
      specialArgs = {
        inherit pkgs-stable;
        inherit systemSettings;
        inherit userSettings;
        inherit inputs;
      };
    };
  };
}
