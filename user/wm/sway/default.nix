{ lib, ... }:

{
  # Internal cross-module wiring (kept minimal).
  #
  # Leaf modules (session-env/startup-apps/...) publish script derivations here so other modules
  # (notably `swayfx-config.nix`) can reference them without duplicating definitions.
  options.user.wm.sway._internal = lib.mkOption {
    internal = true;
    default = { };
    description = "Internal wiring for Sway submodules (implementation detail).";
    type = lib.types.submodule ({ ... }: {
      options.scripts = lib.mkOption {
        internal = true;
        default = { };
        type = lib.types.attrsOf lib.types.package;
        description = "Internal script derivations published by Sway submodules.";
      };
    });
  };

  config.user.wm.sway._internal.scripts = lib.mkDefault { };

  imports = [
    ../../app/terminal/alacritty.nix
    ../../app/terminal/kitty.nix
    ../../app/terminal/tmux.nix
    ../../app/terminal/xterm.nix
    ../../app/gaming/mangohud.nix
    ../../app/ai/aichat.nix
    ../../app/swaybgplus/swaybgplus.nix
    ../../app/swww/swww.nix
    ../../app/waypaper/waypaper.nix
    ../../shell/sh.nix

    ./session-env.nix
    ./session-systemd.nix
    ./kanshi.nix
    ./nwg-displays.nix
    ./workspace-groups-gui.nix
    ./startup-apps.nix
    ./swayfx-config.nix
    ./extras.nix
    ./kde-apps.nix
  ];
}


