{ lib, buildNpmPackage, fetchFromGitHub, fetchurl, nodejs_24 }:
# rea-agents built from our fork (akunito/rea) at the upstream release commit.
let
  # Frida's npm install script (prebuild-install) downloads this at install time; we skip
  # scripts and pin the same prebuilt N-API binding by hash instead. Needs only glibc
  # (readelf: libc/libm/libdl/librt/libpthread, GLIBC_2.5 max).
  fridaBinding = fetchurl {
    url = "https://github.com/frida/frida/releases/download/17.23.2/frida-v17.23.2-napi-v8-linux-x64.tar.gz";
    hash = "sha256-n6j2aM6R6wNxPoVk3k+PveIyIz7pHXKcFnc/3hHbrpU=";
  };
in
buildNpmPackage {
  pname = "rea-agents";
  version = "6.5.0";
  nodejs = nodejs_24;
  src = fetchFromGitHub {
    owner = "akunito";
    repo = "rea";
    rev = "3b79af28e80785afce9f5998d8f03289402a1847"; # tag rea-agents-6.5.0 upstream
    hash = "sha256-fPe+tqkSRR5K+zSVWb6kjI6/HbQSJ8DHjLJwSWu8NzI=";
  };
  npmDepsHash = "sha256-EQKhS1S7Hsfjbo5GikMeAFc2HFtALsDcw6XnJATUryw=";
  # No install scripts: husky is dev tooling; frida's binding is supplied below.
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
    m=$out/lib/node_modules/rea-agents
    rm -f $m/native/windows/build/rea-windows-x64.node
    mkdir -p $m/node_modules/frida/build
    tar -xzf ${fridaBinding} -C $m/node_modules/frida build/frida_binding.node
  '';
  meta.mainProgram = "rea";
}
