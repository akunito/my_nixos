{ pkgs, ghidra ? pkgs.ghidra }:
# M2 (AINF-408): open function-ID signatures for Ghidra, generated from nixpkgs' own
# static libraries (no IDA/FLIRT data, no third-party sig sets). Each library becomes a
# read-only .fidbf inside a Ghidra extension module: FidFileManager loads every .fidbf
# found in any module's data/ (findDeliveredFidFiles), so REA sees them with its empty
# per-session user settings — a user-added .fidb would be invisible there.
let
  lib = pkgs.lib;
  scripts = pkgs.runCommand "rea-fid-scripts" { } "mkdir $out; cp ${./BuildFid.java} $out/BuildFid.java";
  # One headless run imports every archive member (-recursive) and auto-analyses it; a
  # second run on a throwaway trigger file executes BuildFid over the whole project.
  mkFid = { name, family, version, variant ? "x86_64", archives }:
    pkgs.runCommand "rea-fid-${name}"
      { nativeBuildInputs = [ ghidra pkgs.coreutils ]; }
      ''
        export HOME=$TMPDIR GHIDRA_HEADLESS_MAXMEM=6G
        H=${ghidra}/lib/ghidra/support/analyzeHeadless
        mkdir -p $TMPDIR/proj $out
        for a in ${lib.concatStringsSep " " archives}; do
          cp "$a" $TMPDIR/
          $H $TMPDIR/proj lib -import "$TMPDIR/$(basename "$a")" -recursive \
            -max-cpu $NIX_BUILD_CORES -analysisTimeoutPerFile 120 > $TMPDIR/import.log 2>&1 \
            || { tail -40 $TMPDIR/import.log; exit 1; }
        done
        cp ${pkgs.coreutils}/bin/true $TMPDIR/rea-fid-trigger
        $H $TMPDIR/proj lib -import $TMPDIR/rea-fid-trigger -noanalysis -readOnly \
          -scriptPath ${scripts} -postScript BuildFid.java \
          "${family}" "${version}" "${variant}" $out/${name}.fidbf x86:LE:64:default \
          > $TMPDIR/build.log 2>&1 || { tail -40 $TMPDIR/build.log; exit 1; }
        grep -h "REA-FID" $TMPDIR/build.log | tee $out/${name}.summary
        test -s $out/${name}.fidbf || { grep -v "^INFO" $TMPDIR/build.log | tail -30; exit 1; }
        rm -f $out/${name}.fidbf.fidb
      '';
  # The standard set for one nixpkgs: libc (glibc, musl), libstdc++ (both targets), Rust std.
  # tag distinguishes versions in file names (e.g. "u" unstable, "s" stable).
  libSet = p: tag: [
    (mkFid { name = "glibc-${p.glibc.version}"; family = "glibc"; version = p.glibc.version; archives = [ "${p.glibc.static}/lib/libc.a" ]; })
    (mkFid { name = "musl-${p.musl.version}"; family = "musl"; version = p.musl.version; archives = [ "${p.musl}/lib/libc.a" ]; })
    (mkFid { name = "libstdcxx-gnu-${p.stdenv.cc.cc.version}"; family = "libstdc++"; version = p.stdenv.cc.cc.version; variant = "x86_64-linux-gnu"; archives = [ "${p.stdenv.cc.cc}/lib/libstdc++.a" ]; })
    (mkFid { name = "libstdcxx-musl-${p.pkgsStatic.stdenv.cc.cc.version}"; family = "libstdc++"; version = p.pkgsStatic.stdenv.cc.cc.version; variant = "x86_64-linux-musl"; archives = [ "${p.pkgsStatic.stdenv.cc.cc.lib}/x86_64-unknown-linux-musl/lib/libstdc++.a" ]; })
    (mkFid { name = "rust-std-${p.rustc.version}"; family = "rust-std"; version = p.rustc.version; archives = map (l: "${p.rustc.unwrapped}/lib/rustlib/x86_64-unknown-linux-gnu/lib/lib${l}-*.rlib") [ "core" "alloc" "std" ]; })
  ];
in
{
  inherit mkFid libSet;
  # Ghidra extension module carrying the .fidbf files under data/.
  extension = fids: pkgs.runCommand "rea-fid-extension" { } ''
    d=$out/lib/ghidra/Ghidra/Extensions/rea-fid
    mkdir -p $d/data
    printf 'name=rea-fid\ndescription=Function ID databases built from nixpkgs static libraries (AINF-408 M2)\nauthor=rea\ncreatedOn=2026-10-14\nversion=${ghidra.version}\n' > $d/extension.properties
    touch $d/Module.manifest
    ${lib.concatMapStringsSep "\n" (f: "cp ${f}/*.fidbf $d/data/") fids}
  '';
}
