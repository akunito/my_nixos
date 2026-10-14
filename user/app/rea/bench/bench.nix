{ pkgs, label, extraExtensions ? [ ], ghidraHome ? "${pkgs.ghidra}/lib/ghidra", corpus ? import ./corpus.nix { inherit pkgs; } }:
# M1/M2 (AINF-408): the benchmark as a Nix build — same Ghidra and extension wiring as
# env.nix (NIX_GHIDRAHOME, never GHIDRA_INSTALL_DIR), plus optional extra extensions —
# so a candidate (e.g. the M2 FID set) is measured against the baseline before it ever
# reaches REA's image. No network in the build sandbox; corpus = our own programs.
# ghidraHome: another install tree (M3: kuna.nix's tree with Kuna as `decompile`).
let
  ghidraExt = pkgs.ghidra.withExtensions (e: [ e.ghidra-golanganalyzerextension e.findcrypt ] ++ extraExtensions);
  scripts = pkgs.runCommand "rea-bench-scripts" { } "mkdir $out; cp ${./BenchDump.java} $out/BenchDump.java";
in
pkgs.runCommand "rea-bench-${label}" { nativeBuildInputs = [ pkgs.ghidra pkgs.python3 ]; } ''
  export HOME=$TMPDIR GHIDRA_HEADLESS_MAXMEM=4G NIX_GHIDRAHOME=${ghidraExt}/lib/ghidra/Ghidra
  mkdir -p $out/raw $TMPDIR/p
  for t in ${corpus}/*.stripped; do
    id=$(basename $t .stripped); s=$(date +%s)
    ${ghidraHome}/support/analyzeHeadless $TMPDIR/p p -import $t \
      -scriptPath ${scripts} -postScript BenchDump.java $out/raw/$id.json \
      -deleteProject -analysisTimeoutPerFile 1800 > $out/raw/$id.log 2>&1 \
      || { grep -v "^INFO" $out/raw/$id.log | tail -30; exit 1; }
    echo "$id $(( $(date +%s) - s ))" >> $out/times.txt
  done
  python3 -I ${./score.py} ${corpus} $out/raw ${pkgs.binutils-unwrapped}/bin/readelf > $out/score.json
  python3 -I ${./table.py} $out/score.json $out/times.txt > $out/score.txt
''
