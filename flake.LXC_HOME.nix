{
  description = "Flake for LXC_HOME - Homelab services container";

  outputs =
    inputs@{ self, ... }:
    let
      base = import ./lib/flake-base.nix;
      profileConfig = import ./profiles/LXC_HOME-config.nix;
    in
    base { inherit inputs self profileConfig; };

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "nixpkgs/nixos-25.11";

    home-manager-unstable.url = "git+ssh://git@github.com/nix-community/home-manager?ref=master";
    home-manager-unstable.inputs.nixpkgs.follows = "nixpkgs";

    home-manager-stable.url = "git+ssh://git@github.com/nix-community/home-manager?ref=release-25.11";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";

    blocklist-hosts = {
      url = "github:StevenBlack/hosts";
      flake = false;
    };
  };
}
