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
          # Archived (akunito LXCs decommissioned — workload moved to VPS_PROD
          # and NAS_PROD; profiles preserved in profiles/archived/):
          # LXC_HOME, LXC_tailscale, LXC_proxy, LXC_database, LXC_monitoring,
          # LXC_mailer, LXC_plane, LXC_matrix, LXC_liftcraftTEST, LXC_portfolioprod
          KOMI_LXC_database = ./profiles/KOMI_LXC_database-config.nix;
          KOMI_LXC_mailer = ./profiles/KOMI_LXC_mailer-config.nix;
          KOMI_LXC_monitoring = ./profiles/KOMI_LXC_monitoring-config.nix;
          KOMI_LXC_proxy = ./profiles/KOMI_LXC_proxy-config.nix;
          KOMI_LXC_tailscale = ./profiles/KOMI_LXC_tailscale-config.nix;
          VPS_PROD = ./profiles/VPS_PROD-config.nix;
          NAS_PROD = ./profiles/NAS_PROD-config.nix;
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
      # Track Stylix's release-25.11 branch (matches our nixos-25.11 stable
      # base). Avoids 26.05-only NixOS option assumptions in Stylix's modules
      # (e.g. services.displayManager.generic). When we bump nixpkgs-stable
      # to 26.04 in the future, also bump this branch suffix to release-26.04
      # in lockstep — a once-per-year one-line change.
      url = "github:danth/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs-stable";
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

    # Zen Browser — not in nixpkgs (NixOS/nixpkgs#327982). This flake wraps the
    # upstream build with nixpkgs' wrapFirefox, so `.override { extraPrefsFiles }`
    # works — that's what lets user/app/browser/zen.nix ship the Sine bootloader.
    #
    # PINNED 2026-08-20 to 044be1a. Newer revs make the Home-Manager module reach
    # firefox/wrapper.nix with `ffmpeg_8`:
    #   error: function 'anonymous lambda' called with unexpected argument
    #   'ffmpeg_8' ... Did you mean ffmpeg_7?
    #
    # The follows below is a red herring — it only sets the nixpkgs used to build
    # zen itself. The module calls `pkgs.wrapFirefox` with HOME MANAGER's pkgs,
    # which is pkgs-STABLE, and 25.11's wrapper.nix takes ffmpeg_7 only. Unstable
    # already takes both ffmpeg_7 and ffmpeg_8, so stable is the broken side —
    # pointing the follows at nixpkgs-stable makes this worse, not better.
    # Breaks Home Manager only; the system build is unaffected.
    #
    # Because `install.sh -u` runs `nix flake update`, leaving this unpinned
    # re-breaks HM on every update. Drop the rev when nixpkgs-stable is bumped to
    # a release whose firefox/wrapper.nix accepts ffmpeg_8. Check with:
    #   grep -n '^  ffmpeg' "$(nix eval --impure --raw --expr \
    #     '(builtins.getFlake "/home/akunito/.dotfiles").inputs.nixpkgs-stable.outPath')\
    #     /pkgs/applications/networking/browsers/firefox/wrapper.nix"
    # then verify with:
    #   nix eval --impure --raw .#homeConfigurations.DESK.activationPackage.drvPath
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake/044be1aba87c30d42568e817c78a94c1d8eacb14";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Our fork of the sine-web-panels Zen mod (restores Vivaldi-style sidebar
    # web panels). Tracks the `akunito/local` branch, which carries the local
    # patches on top of upstream: the panel-tab-active fix (sent upstream as
    # dehyde/sine-web-panels#2) and the configurable panel shortcut.
    # Consumed by user/app/browser/zen.nix; `flake = false` because the repo is
    # a plain mod, not a flake. Bump with:
    #   nix flake update sine-web-panels
    sine-web-panels = {
      url = "github:akunito/sine-web-panels/akunito/local";
      flake = false;
    };

    # Voice dictation (Whisper-based, local)
    # Pinned: newer revs (e.g. ddc93de) fail to build — missing xorg.libX11 in Rust build inputs.
    voxtype = {
      url = "github:peteonrails/voxtype/adf0ea62c2310b90c55febdc6515cca9f264e25a";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # FreeSM Launcher (Freesm Launcher) — Prism Launcher fork with offline accounts.
    # Consumed as packages.<system>.default in system/app/freesm-launcher.nix.
    # NOTE: nixpkgs deliberately NOT following ours — keeping upstream's locked
    # nixpkgs lets us pull prebuilt binaries from their Cachix (see nix.settings
    # in the module) instead of a heavy local Qt source build.
    freesm-launcher.url = "github:FreesmTeam/FreesmLauncher/develop";
  };
}
