{ pkgs }:
# JEB Community Edition 5.48 (PNF Software; free, per-user; licence key inside the zip, valid
# to 2030) for REA's JEB provider (AINF-408 F6). REA verified JEB 5.48; it talks to JEB's own
# MCP server (`jeb.jar -c --mcp`, default 127.0.0.1:8425/mcp). The zip cannot be fetched
# (download form): add it once with
#   nix-store --add-fixed sha256 ~/Downloads/jeb-ce-5.48.0.202610071539-JEBDecompiler-624458483834837192.zip
# EULA (pnfsoftware.com/jeb/LICENSE.TXT, rev 2026-02-04): output may not be made available to
# third parties — see docs/akunito/plans/rea-sandbox/herramientas.md before using it with a
# cloud model.
let
  zip = pkgs.requireFile {
    name = "jeb-ce-5.48.0.202610071539-JEBDecompiler-624458483834837192.zip";
    sha256 = "709e7fe8e88bb0e9e2bc03b028f8b9fc78cec0289d04abe54fc26cda6369e175";
    message = "Download JEB CE 5.48 from https://www.pnfsoftware.com/jeb/community-edition, then: nix-store --add-fixed sha256 <zip>";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "jeb-ce";
  version = "5.48.0";
  src = zip;
  nativeBuildInputs = [ pkgs.unzip ];
  dontFixup = true;
  unpackPhase = "unzip -q $src -d src";
  installPhase = ''
    mkdir -p $out/opt
    # The GUI (SWT) and the updater/installer are not needed headless; the read-only store
    # copy runs in JEB's "shared" mode (-Djeb.sharedProgram), which also skips jebi.jar --up.
    cp -r src $out/opt/jeb
    rm -rf $out/opt/jeb/bin/app/.swt
  '';
  passthru.zip = zip;
}
