{ pkgs, rea-agents }:
# REA sandbox image for tier 0 (AINF-408 F1): rootless Docker + krun. Tools and
# environment come from env.nix, shared with the microVM guest (vm.nix).
let
  reaEnv = import ./env.nix { inherit pkgs rea-agents; };
  nss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = [ "rea:x:1000:100:rea:/tmp:/bin/sh" ];
    extraGroupLines = [ "users:x:100:" ];
  };
in
pkgs.dockerTools.buildLayeredImage {
  name = "rea-sandbox";
  tag = null; # content hash: a new build never reuses a loaded tag
  contents = reaEnv.tools ++ [ nss pkgs.dockerTools.binSh ];
  config = {
    User = "1000:100";
    Entrypoint = [ "${rea-agents}/bin/rea" ];
    Env = pkgs.lib.mapAttrsToList (k: v: "${k}=${v}") reaEnv.env;
  };
}
