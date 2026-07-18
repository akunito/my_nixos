# Minecraft Client (PrismLauncher + JDK)
#
# FOSS launcher stack for connecting to the self-hosted AkuCraft server
# (Fabric 1.21.1, offline mode, reachable over Tailscale at 100.64.0.6:25565).
#
# Gated by systemSettings.minecraftClientEnable — imported conditionally from
# profiles/personal/configuration.nix; enabled on DESK + LAPTOP_X13 only.
#
# Notes:
# - PrismLauncher is the upstream FOSS launcher. Its offline-account feature is
#   gated behind at least one Microsoft account that owns Minecraft. Adding an
#   account is a manual, per-machine step done inside the launcher GUI.
# - Minecraft 1.21.x requires Java 21; older packs may need Java 17/8. We ship
#   JDK 21 + 17 and let PrismLauncher auto-detect (Settings -> Java) rather than
#   relying on Mojang's bundled JRE (a downloaded glibc binary won't run on NixOS).

{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    prismlauncher # FOSS Minecraft launcher (multi-instance, Fabric/Forge/Quilt)
    jdk21 # Java 21 — required by Minecraft 1.21.x (AkuCraft server)
    jdk17 # Java 17 — for older instances / modpacks
    glfw # System GLFW (PrismLauncher: "Use system installation of GLFW" for Wayland)
  ];
}
