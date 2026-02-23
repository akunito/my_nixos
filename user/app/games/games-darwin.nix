# macOS Gaming packages (Darwin-only)
# Controlled by: userSettings.gamesEnable
# This is the macOS counterpart of games.nix (Linux).
# GUI apps (Steam, OpenEmu) are managed via Homebrew casks in the profile config.
# Nix packages here are tools and games available in nixpkgs for aarch64-darwin.
#
# Not available on macOS: pegasus-frontend, antimicrox, superTux (Linux only)
# Build broken on macOS: superTuxKart (WiiUse dep fails on darwin)
{
  pkgs,
  pkgs-unstable,
  userSettings,
  lib,
  ...
}:
{
  home.packages =
    (with pkgs; [
      # === Wine Wrapper ===
      # Whisky: SwiftUI Wine wrapper for running Windows games (e.g. Warblade)
      # Note: upstream archived May 2025 (v2.3.5), but the Nix package works fine for old games.
      # If a future macOS update breaks it, consider CrossOver (commercial) or a community fork.
      whisky
    ])
    ++ [
      # === Gaming Mode Toggle ===
      # Pauses Spotlight indexing and Time Machine during gaming sessions
      (pkgs.writeShellScriptBin "game-mode" (builtins.readFile ./game-mode-darwin.sh))
    ];
}
