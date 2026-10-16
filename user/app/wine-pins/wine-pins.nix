# Pinned Wine / GE-Proton next to the gaming Wine (games-heavy.nix), never shadowing it.
# Docs: docs/user-modules/wine-pins.md. Commands: wpinN, wineN, wpinN-ge (N = pin number).
#   winePinsEnable -> pins 2-5 from the public flake input `wine-pins` (rev pinned in flake.nix).
#   winePin1Enable -> pin 1 from the PRIVATE repo akunito/wine-pin1. It is not a flake input on purpose:
#     update.sh runs `sudo nix flake update`, root has no GitHub credentials, and a private input would
#     break that on every machine. These wrappers build it on first use as the user (SSH key) into a
#     GC root under ~/.local/state/wine-pins, then exec from there.
{
  pkgs,
  lib,
  userSettings,
  inputs,
  ...
}:
let
  # Bump after pushing akunito/wine-pin1 (its README: "Moving the pin").
  winePin1Rev = "014b70ce0cb8bf17087aae766293b1b57b7d8936";
  winePin1Ref = "git+ssh://git@github.com/akunito/wine-pin1?rev=${winePin1Rev}#default";

  pin1Cmd =
    cmd:
    pkgs.writeShellScriptBin cmd ''
      root="''${XDG_STATE_HOME:-$HOME/.local/state}/wine-pins/pin1-${winePin1Rev}"
      if [ ! -x "$root/bin/${cmd}" ]; then
        mkdir -p "$(dirname "$root")"
        echo "wine-pin1: first use, building ${winePin1Rev} ..." >&2
        nix build --out-link "$root" '${winePin1Ref}' >&2 || exit 1
      fi
      exec "$root/bin/${cmd}" "$@"
    '';
in
{
  config = lib.mkMerge [
    (lib.mkIf (userSettings.winePinsEnable or false) {
      home.packages = [ inputs.wine-pins.packages.${pkgs.stdenv.hostPlatform.system}.default ];
    })
    (lib.mkIf (userSettings.winePin1Enable or false) {
      home.packages = map pin1Cmd [ "wpin1" "wine1" "wpin1-ge" ];
    })
  ];
}
