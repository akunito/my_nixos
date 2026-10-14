{ lib, buildNpmPackage, fetchFromGitHub, nodejs_24 }:
# rea-agents 6.4.0 built from our fork (akunito/rea) at the upstream release commit.
buildNpmPackage {
  pname = "rea-agents";
  version = "6.4.0";
  nodejs = nodejs_24;
  src = fetchFromGitHub {
    owner = "akunito";
    repo = "rea";
    rev = "a56f7bb668ab23fec8d33f7af353ac7ed2fe1895"; # tag rea-agents-6.4.0 upstream
    hash = "sha256-aAbOYpsT6QhlLAZDtVHZ1Acz6uIqrVEd4p49s/2FJgc=";
  };
  npmDepsHash = "sha256-XuiMtaM/MPDkhjiHCr9dGC7WlsRBmsWepuNHRxAs3Nw=";
  # frida's install script downloads a prebuilt from GitHub (fails in the sandbox
  # and is only needed for the dynamic lane, F3); husky is dev tooling.
  npmFlags = [ "--ignore-scripts" ];
  npmPackFlags = [ "--ignore-scripts" ];
  env = { HUSKY = "0"; TURBO_TELEMETRY_DISABLED = "1"; };
  buildPhase = ''
    runHook preBuild
    npm run compile
    node scripts/generate-skill-metadata.mjs
    runHook postBuild
  '';
  # Windows-only prebuilt blob; not reproducible and never used on Linux.
  postInstall = ''
    rm -f $out/lib/node_modules/rea-agents/native/windows/build/rea-windows-x64.node
  '';
  meta.mainProgram = "rea";
}
