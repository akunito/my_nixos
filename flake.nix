{
  description = "Unified NixOS/Darwin flake with all profiles";

  # ============================================================================
  # OUTPUTS
  # ============================================================================
  # Generates:
  #   - nixosConfigurations.DESK, nixosConfigurations.LAPTOP_L15, etc.
  #   - darwinConfigurations.MACBOOK-KOMI, etc.
  #   - homeConfigurations.DESK, homeConfigurations.LAPTOP_L15, etc.
  #   - Backward compat aliases: nixosConfigurations.system, homeConfigurations.user
  #
  # Usage:
  #   nixos-rebuild switch --flake .#DESK
  #   nixos-rebuild switch --flake .#system  # Uses .active-profile
  #   darwin-rebuild switch --flake .#MACBOOK-KOMI
  # ============================================================================

  outputs = inputs@{ self, ... }:
    let
      mkUnified = import ./lib/flake-unified.nix;
    in
      mkUnified {
        inherit inputs self;
        profiles = {
          # ====================================================================
          # Desktop Profiles
          # ====================================================================
          DESK = ./profiles/DESK-config.nix;
          DESK_AGA = ./profiles/DESK_AGA-config.nix;
          DESK_VMDESK = ./profiles/DESK_VMDESK-config.nix;

          # ====================================================================
          # Laptop Profiles
          # ====================================================================
          LAPTOP_L15 = ./profiles/LAPTOP_L15-config.nix;
          LAPTOP_AGA = ./profiles/LAPTOP_AGA-config.nix;
          LAPTOP_YOGAAKU = ./profiles/LAPTOP_YOGAAKU-config.nix;

          # ====================================================================
          # Homelab Profiles
          # ====================================================================
          HOME = ./profiles/HOME-config.nix;
          VMHOME = ./profiles/VMHOME-config.nix;

          # ====================================================================
          # LXC Container Profiles
          # ====================================================================
          LXC = ./profiles/LXC-config.nix;
          LXC_HOME = ./profiles/LXC_HOME-config.nix;
          LXC_database = ./profiles/LXC_database-config.nix;
          LXC_liftcraftTEST = ./profiles/LXC_liftcraftTEST-config.nix;
          LXC_mailer = ./profiles/LXC_mailer-config.nix;
          LXC_matrix = ./profiles/LXC_matrix-config.nix;
          LXC_monitoring = ./profiles/LXC_monitoring-config.nix;
          LXC_plane = ./profiles/LXC_plane-config.nix;
          LXC_portfolioprod = ./profiles/LXC_portfolioprod-config.nix;
          LXC_proxy = ./profiles/LXC_proxy-config.nix;
          LXC_tailscale = ./profiles/LXC_tailscale-config.nix;

          # ====================================================================
          # macOS/Darwin Profiles
          # ====================================================================
          MACBOOK-KOMI = ./profiles/MACBOOK-KOMI-config.nix;

          # ====================================================================
          # WSL Profile
          # ====================================================================
          WSL = ./profiles/WSL-config.nix;
        };
      };

  # ============================================================================
  # INPUTS - Superset of all profile dependencies
  # ============================================================================
  # Note: Nix uses lazy evaluation, so unused inputs are not fetched.
  # Only inputs required by the profile being built will be downloaded.
  # ============================================================================

  inputs = {
    # --------------------------------------------------------------------------
    # Core Nixpkgs
    # --------------------------------------------------------------------------
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-25.11";

    # --------------------------------------------------------------------------
    # Home Manager
    # --------------------------------------------------------------------------
    home-manager-unstable.url = "github:nix-community/home-manager/master";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-stable.url = "github:nix-community/home-manager/release-25.11";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    # --------------------------------------------------------------------------
    # Darwin (macOS) Support
    # --------------------------------------------------------------------------
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------
    # Desktop Environment & Theming
    # --------------------------------------------------------------------------
    hyprland = {
      url = "github:hyprwm/Hyprland/main?submodules=true";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------
    # Development Tools
    # --------------------------------------------------------------------------
    rust-overlay.url = "github:oxalica/rust-overlay";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------
    # Hardware Support
    # --------------------------------------------------------------------------
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # --------------------------------------------------------------------------
    # Gaming
    # --------------------------------------------------------------------------
    nix-citizen.url = "github:LovingMelody/nix-citizen";
    nix-citizen.inputs.nixpkgs.follows = "nixpkgs";

    # --------------------------------------------------------------------------
    # Security & Networking
    # --------------------------------------------------------------------------
    blocklist-hosts = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };
  };
}
