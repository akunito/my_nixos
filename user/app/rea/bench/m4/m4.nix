{ pkgs }:
# M4 benchmark (AINF-408), HumanEval-Decompile style on our own functions:
#   dump  — the corpus (gcc -O0, gcc -O2, clang -O2; PIE, stripped) and Ghidra's C for each
#           function, exactly as REA's Ghidra produces it (same extensions as env.nix);
#   eval  — compile a candidate per function (Ghidra's own C, or a model's rewrite stored in
#           workbench/rea-bench/m4-llm) against funcs.c and run harness.c: compiles / PASS.
# Candidates are model output: they are only ever compiled and run here, in the Nix
# build sandbox (no network, own uid, throwaway), never on the host.
let
  lib = pkgs.lib;
  fns = [ "fnv1a" "upcase" "count_bits" "gcd" "is_prime" "reverse" "checksum16" "bsearch_int"
          "sort_ints" "rot13" "parse_int" "max_subarray" "crc8" "clamp" ];
  builds = { gcc-O0 = "gcc -O0"; gcc-O2 = "gcc -O2"; clang-O2 = "clang -O2"; };
  ghidraExt = pkgs.ghidra.withExtensions (e: [ e.ghidra-golanganalyzerextension e.findcrypt ]);
  scripts = pkgs.runCommand "rea-m4-scripts" { } "mkdir $out; cp ${./DumpC.java} $out/DumpC.java";
  corpus = pkgs.runCommandCC "rea-m4-corpus" { nativeBuildInputs = [ pkgs.clang pkgs.binutils ]; hardeningDisable = [ "fortify" ]; } ''
    mkdir -p $out
    ${lib.concatStrings (lib.mapAttrsToList (b: cc: ''
      ${cc} -o $out/${b} ${./funcs.c} ${./main.c}
      cp $out/${b} $out/${b}.stripped; chmod u+w $out/${b}.stripped; strip --strip-all $out/${b}.stripped
    '') builds)}
  '';
in
{
  inherit corpus fns;
  dump = pkgs.runCommand "rea-m4-ghidra-c" { nativeBuildInputs = [ pkgs.binutils-unwrapped pkgs.gawk ]; } ''
    export HOME=$TMPDIR GHIDRA_HEADLESS_MAXMEM=4G NIX_GHIDRAHOME=${ghidraExt}/lib/ghidra/Ghidra
    for b in ${lib.concatStringsSep " " (lib.attrNames builds)}; do
      mkdir -p $out/$b $TMPDIR/p
      args=$(readelf -sW ${corpus}/$b | awk '$4=="FUNC" && $7!="UND" {print $8"=0x"$2}' \
        | grep -E '^(${lib.concatStringsSep "|" fns})=' | tr '\n' ' ')
      ${pkgs.ghidra}/lib/ghidra/support/analyzeHeadless $TMPDIR/p p -import ${corpus}/$b.stripped \
        -scriptPath ${scripts} -postScript DumpC.java $out/$b $args -deleteProject > $TMPDIR/$b.log 2>&1 \
        || { tail -30 $TMPDIR/$b.log; exit 1; }
    done
  '';
  # candidates: a directory <build>/<fn>.c ; label names the result.
  eval = label: candidates: pkgs.runCommandCC "rea-m4-eval-${label}"
    { nativeBuildInputs = [ pkgs.gcc pkgs.binutils pkgs.coreutils pkgs.python3 ]; hardeningDisable = [ "all" ]; } ''
    mkdir -p $out/logs
    cat > prelude.h <<'EOF'
    #include <stdint.h>
    #include <stdbool.h>
    #include <stdlib.h>
    #include <string.h>
    #include <ctype.h>
    typedef unsigned char byte, undefined, undefined1, uchar;
    typedef unsigned short ushort, undefined2, word;
    typedef unsigned int uint, undefined4, dword;
    typedef unsigned long ulong, undefined8, qword;
    typedef long long longlong;
    typedef unsigned long long ulonglong;
    typedef unsigned char uint8; typedef unsigned short uint16; typedef unsigned int uint32;
    EOF
    gcc -O1 -c ${./funcs.c} -o ref.o
    for f in ${lib.concatStringsSep " " fns}; do objcopy --redefine-sym $f=ref_$f ref.o; done
    : > $out/results.tsv
    for b in ${lib.concatStringsSep " " (lib.attrNames builds)}; do
      for f in ${lib.concatStringsSep " " fns}; do
        c=${candidates}/$b/$f.c; st=missing
        if [ -f "$c" ]; then
          # The candidate's function name -> cand (first function definition in the file).
          name=$(python3 -I -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"(\w+)\s*\([^;{}()]*\)\s*\{", t); print(m.group(1) if m else "")' "$c")
          { cat prelude.h; cat "$c"; } > cand.c
          if [ -n "$name" ] && gcc -w -O1 -std=gnu11 -D$name=cand -c cand.c -o cand.o 2> $out/logs/$b-$f.cc.log; then
            if gcc -w -O1 -DFN_$f ${./harness.c} cand.o ref.o -o t 2>> $out/logs/$b-$f.cc.log; then
              timeout 10 ./t > $out/logs/$b-$f.run.log 2>&1 && st=pass || st=fail
            else st=nolink; fi
          else st=nocompile; fi
        fi
        printf '%s\t%s\t%s\n' "$b" "$f" "$st" >> $out/results.tsv
      done
    done
    awk -F'\t' '{n[$1]++; s[$1","$3]++} END {for (b in n) printf "%s: pass %d/%d, fail %d, no-compile %d, no-link %d\n", b, s[b",pass"], n[b], s[b",fail"], s[b",nocompile"], s[b",nolink"]}' $out/results.tsv | sort > $out/summary.txt
  '';
}
