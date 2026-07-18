# FreeSM Launcher (Freesm Launcher)
#
# A Prism Launcher fork that removes offline-account restrictions and adds
# custom auth-server support — used for the self-hosted offline-mode AkuCraft
# server (Fabric 1.21.1, reachable over Tailscale at 100.64.0.6:25565).
#
# Replaces the old PrismLauncher module (system/app/minecraft-client.nix).
#
# Gated by systemSettings.freesmLauncherEnable — imported conditionally from
# profiles/personal/configuration.nix; enabled on DESK + LAPTOP_X13 only.
#
# Packaging notes:
# - Uses the OFFICIAL flake from FreesmTeam (inputs.freesm-launcher), consumed as
#   packages.<system>.default. That wrapper is fully self-contained: it bundles
#   the OpenJDK 8/17/21/25 JVMs and every runtime lib (GL/Vulkan/Wayland GLFW,
#   controller, gamemode, audio), so no separate JDK/GLFW packages are needed and
#   there is no Flatpak runtime involved.
# - We add upstream's Cachix as a substituter so `nixos-rebuild` pulls a prebuilt
#   binary instead of compiling Qt/the launcher from source. The upstream flake's
#   own nixConfig does not propagate to our top-level flake, so it must be set here.
#   The flake input intentionally does NOT follow our nixpkgs (see flake.nix) so
#   the cached artifacts match.

{ pkgs, inputs, ... }:

{
  environment.systemPackages = [
    inputs.freesm-launcher.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Pull prebuilt binaries from upstream's Cachix (avoids a local source build).
  nix.settings = {
    substituters = [ "https://freesmlauncher.cachix.org" ];
    trusted-public-keys = [
      "freesmlauncher.cachix.org-1:Jcp5Q9wiLL+EDv8Mh7c6L9xGk+lXr7/otpKxMOuBuDs="
    ];
  };
}
