{ pkgs }:
# M2: binaries built with Debian/Ubuntu/Alpine toolchains (workbench/rea-bench/foreign-corpus,
# git-crypt: needs the repo unlocked). Same layout as corpus.nix: <id> with symbols and
# <id>.stripped, stripped here so only one copy lives in git.
pkgs.runCommand "rea-bench-foreign-corpus" { nativeBuildInputs = [ pkgs.binutils ]; } ''
  mkdir -p $out
  for f in ${../../../../workbench/rea-bench/foreign-corpus}/c-* ${../../../../workbench/rea-bench/foreign-corpus}/cpp-*; do
    b=$(basename $f)
    cp $f $out/$b
    cp $f $out/$b.stripped
    chmod u+w $out/$b.stripped
    strip --strip-all $out/$b.stripped
  done
''
