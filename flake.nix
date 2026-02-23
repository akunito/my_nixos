{
  description = "Unified NixOS/nix-darwin flake for all profiles";

  outputs = inputs@{ self, ... }:
    let
      mkUnified = import ./lib/flake-unified.nix;
    in
      mkUnified {
        inherit inputs self;
        profiles = {
          DESK = ./profiles/DESK-config.nix;
          DESK_A = ./profiles/DESK_A-config.nix;
          DESK_VMDESK = ./profiles/DESK_VMDESK-config.nix;
          LAPTOP_X13 = ./profiles/LAPTOP_X13-config.nix;
          LAPTOP_A = ./profiles/LAPTOP_A-config.nix;
          LAPTOP_YOGA = ./profiles/LAPTOP_YOGA-config.nix;
          VMHOME = ./profiles/VMHOME-config.nix;
          WSL = ./profiles/WSL-config.nix;
          LXC_HOME = ./profiles/LXC_HOME-config.nix;
          LXC_tailscale = ./profiles/LXC_tailscale-config.nix;
          # Archived (migrated to VPS_PROD / TrueNAS — profiles in profiles/archived/):
          # LXC_proxy, LXC_database, LXC_monitoring, LXC_mailer,
          # LXC_plane, LXC_matrix, LXC_liftcraftTEST, LXC_portfolioprod
          KOMI_LXC_database = ./profiles/KOMI_LXC_database-config.nix;
          KOMI_LXC_mailer = ./profiles/KOMI_LXC_mailer-config.nix;
          KOMI_LXC_monitoring = ./profiles/KOMI_LXC_monitoring-config.nix;
          KOMI_LXC_proxy = ./profiles/KOMI_LXC_proxy-config.nix;
          KOMI_LXC_tailscale = ./profiles/KOMI_LXC_tailscale-config.nix;
          VPS_PROD = ./profiles/VPS_PROD-config.nix;
          MACBOOK-KOMI = ./profiles/MACBOOK-KOMI-config.nix;
        };
      };

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-25.11";

    home-manager-unstable.url = "github:nix-community/home-manager/master";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-stable.url = "github:nix-community/home-manager/release-25.11";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    hyprland = {
      url = "github:hyprwm/Hyprland/main?submodules=true";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay.url = "github:oxalica/rust-overlay";

    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    blocklist-hosts = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };

    # nix-citizen uses its own nixpkgs pin (wine-astral is incompatible with latest nixpkgs-unstable)
    nix-citizen.url = "github:LovingMelody/nix-citizen";

    # Darwin (macOS) support
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware-specific configurations (used by LAPTOP profiles)
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };
}
