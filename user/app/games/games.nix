# Gaming module dispatcher
# Master gate: gamesEnable (checked in personal/home.nix before importing)
# Each submodule checks its own flag internally via lib.mkIf
{ ... }:
{
  imports = [
    ./games-light.nix # Light gaming: RetroArch, emulators, light games (gamesLightEnable)
    ./games-heavy.nix # Heavy gaming: Wine, Bottles, Lutris, Proton (protongamesEnable)
  ];
}
