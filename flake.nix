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
          DESK_AGA = ./profiles/DESK_AGA-config.nix;
          DESK_VMDESK = ./profiles/DESK_VMDESK-config.nix;
          LAPTOP_L15 = ./profiles/LAPTOP_L15-config.nix;
          LAPTOP_AGA = ./profiles/LAPTOP_AGA-config.nix;
          LAPTOP_YOGAAKU = ./profiles/LAPTOP_YOGAAKU-config.nix;
          VMHOME = ./profiles/VMHOME-config.nix;
          WSL = ./profiles/WSL-config.nix;
          LXC_HOME = ./profiles/LXC_HOME-config.nix;
          LXC_proxy = ./profiles/LXC_proxy-config.nix;
          LXC_plane = ./profiles/LXC_plane-config.nix;
          LXC_mailer = ./profiles/LXC_mailer-config.nix;
          LXC_liftcraftTEST = ./profiles/LXC_liftcraftTEST-config.nix;
          LXC_portfolioprod = ./profiles/LXC_portfolioprod-config.nix;
          LXC_database = ./profiles/LXC_database-config.nix;
          LXC_tailscale = ./profiles/LXC_tailscale-config.nix;
          LXC_monitoring = ./profiles/LXC_monitoring-config.nix;
          LXC_matrix = ./profiles/LXC_matrix-config.nix;
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
