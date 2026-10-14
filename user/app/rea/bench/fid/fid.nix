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
          # glibc 2.40's libm.a is a linker script (GROUP ( libm-2.40.a libmvec.a ), measured):
          # list both names and keep only real ar archives.
          [ "$(head -c 7 "$a" 2>/dev/null)" = '!<arch>' ] || continue
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
  # FID from a LINKED static executable instead of the archive's relocatable objects.
  # ld relaxes code when it links statically — TLS initial-exec becomes local-exec
  # (`mov x@GOTTPOFF(%rip),%rax` -> `mov $imm,%rax`), GOTPCRELX loads become lea/mov $imm —
  # changing opcodes/operand types while keeping the instruction count, so FID's full hash
  # of the object never matches the binary (measured 2026-10-15: Debian 12 free, malloc,
  # calloc, fgets, fclose, perror: same code-unit count, different full hash). Hashing the
  # functions as ld leaves them in a non-PIE static link fixes that. `syms` = archives whose
  # global functions are forced in (EXTERN); `link` = everything needed to resolve them;
  # unresolved leftovers are ignored (the code is hashed, never run).
  mkLinkedFid = { name, family, version, variant ? "x86_64-linked-static", syms, link, crtPre, crtPost }:
    pkgs.runCommand "rea-fid-${name}"
      { nativeBuildInputs = [ ghidra pkgs.coreutils pkgs.binutils-unwrapped pkgs.gawk pkgs.stdenv.cc ]; }
      ''
        export HOME=$TMPDIR GHIDRA_HEADLESS_MAXMEM=6G
        H=${ghidra}/lib/ghidra/support/analyzeHeadless
        mkdir -p $TMPDIR/proj $out
        cd $TMPDIR
        for a in ${lib.concatStringsSep " " syms}; do
          [ "$(head -c 7 "$a" 2>/dev/null)" = '!<arch>' ] || continue
          nm -g --defined-only "$a" 2>/dev/null | awk '$2 ~ /^[TW]$/ {print $3}'
        done | sort -u | awk 'BEGIN{print "EXTERN("} {print "\"" $1 "\""} END{print ")"}' > externs.ld   # quoted: libm names broke the script syntax (measured)
        echo 'int main(void){return 0;}' > m.c && cc -O2 -fno-pie -c m.c -o m.o
        arch=""; for a in ${lib.concatStringsSep " " link}; do [ "$(head -c 7 "$a" 2>/dev/null)" = '!<arch>' ] && arch="$arch $a"; done
        ld -static -o linked ${lib.concatStringsSep " " crtPre} m.o externs.ld --start-group $arch --end-group           ${lib.concatStringsSep " " crtPost} --unresolved-symbols=ignore-all --allow-multiple-definition -z noexecstack 2> ld.log           || { tail -20 ld.log; exit 1; }
        echo "linked $(nm linked | grep -c ' [Tt] ') text symbols" > $out/${name}.summary
        # Two runs, as in mkFid: during a post-script of the importing run the program is not
        # saved in the project yet, so BuildFid found nothing (createNewLibraryFromPrograms
        # returned null, measured).
        $H $TMPDIR/proj lib -import $TMPDIR/linked -max-cpu $NIX_BUILD_CORES -analysisTimeoutPerFile 3600 \
          > $TMPDIR/import.log 2>&1 || { tail -40 $TMPDIR/import.log; exit 1; }
        cp ${pkgs.coreutils}/bin/true $TMPDIR/rea-fid-trigger
        $H $TMPDIR/proj lib -import $TMPDIR/rea-fid-trigger -noanalysis -readOnly \
          -scriptPath ${scripts} -postScript BuildFid.java \
          "${family}" "${version}" "${variant}" $out/${name}.fidbf x86:LE:64:default \
          > $TMPDIR/build.log 2>&1 || { tail -40 $TMPDIR/build.log; exit 1; }
        grep -h "REA-FID" $TMPDIR/build.log | tee -a $out/${name}.summary
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
    # Unwinder/personality and libm: in every static C/C++ binary (audit: unmatched in truth).
    (mkFid { name = "libgcc-${p.stdenv.cc.cc.version}"; family = "libgcc"; version = p.stdenv.cc.cc.version; archives = map (l: "${p.stdenv.cc.cc}/lib/gcc/x86_64-unknown-linux-gnu/${p.stdenv.cc.cc.version}/${l}.a") [ "libgcc" "libgcc_eh" ]; })
    (mkFid { name = "glibc-libm-${p.glibc.version}"; family = "glibc-libm"; version = p.glibc.version; archives = [ "${p.glibc.static}/lib/libm.a" "${p.glibc.static}/lib/libm-*.a" ]; })
    (mkFid { name = "rust-std-${p.rustc.version}"; family = "rust-std"; version = p.rustc.version; archives = map (l: "${p.rustc.unwrapped}/lib/rustlib/x86_64-unknown-linux-gnu/lib/lib${l}-*.rlib") [ "core" "alloc" "std" ]; })
  ];
in
{
  inherit mkFid mkLinkedFid libSet;
  # Ghidra extension module carrying the .fidbf files under data/.
  extension = fids: pkgs.runCommand "rea-fid-extension" { } ''
    d=$out/lib/ghidra/Ghidra/Extensions/rea-fid
    mkdir -p $d/data
    printf 'name=rea-fid\ndescription=Function ID databases built from nixpkgs static libraries (AINF-408 M2)\nauthor=rea\ncreatedOn=2026-10-14\nversion=${ghidra.version}\n' > $d/extension.properties
    touch $d/Module.manifest
    ${lib.concatMapStringsSep "\n" (f: "cp ${f}/*.fidbf $d/data/") fids}
  '';
}
