{ pkgs }:
# M1 corpus (AINF-408): our own programs built with several toolchains / -O levels /
# linkage. Each binary <id> keeps its symbols (ground truth); <id>.stripped is what the
# decompiler sees. Static builds carry libc/libstdc++/Rust std/Go runtime code: that is
# where signatures (M2) can name functions.
# One derivation per toolchain: a musl cc in a glibc stdenv picked up glibc.static from
# NIX_LDFLAGS and failed to link (undefined _DYNAMIC, measured).
let
  src = ./src;
  build = stdenv: name: extra: cmds: stdenv.mkDerivation {
    inherit name;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.binutils ] ++ extra.native or [ ];
    buildInputs = extra.inputs or [ ];
    dontStrip = true;
    dontPatchELF = true;
    hardeningDisable = [ "fortify" ];
    buildPhase = ''
      export HOME=$TMPDIR GOCACHE=$TMPDIR/go-cache CGO_ENABLED=0 GOFLAGS=-trimpath
      mkdir -p $out
      b() { id=$1; shift; "$@"; cp $out/$id $out/$id.stripped; strip --strip-all $out/$id.stripped; }
      ${cmds}
    '';
    installPhase = "true";
  };
  glibcDyn = build pkgs.stdenv "rea-bench-glibc" { native = [ pkgs.clang ]; } ''
    b c-gcc-O0       gcc -O0 -o $out/c-gcc-O0 ${src}/prog.c
    b c-gcc-O2       gcc -O2 -o $out/c-gcc-O2 ${src}/prog.c
    b c-clang-O2     clang -O2 -o $out/c-clang-O2 ${src}/prog.c
    b cpp-gxx-O2     g++ -O2 -std=c++17 -o $out/cpp-gxx-O2 ${src}/prog.cpp
  '';
  glibcStatic = build pkgs.stdenv "rea-bench-glibc-static" { inputs = [ pkgs.glibc.static ]; } ''
    b c-gcc-O2-static-glibc gcc -O2 -static -o $out/c-gcc-O2-static-glibc ${src}/prog.c
  '';
  musl = build pkgs.pkgsStatic.stdenv "rea-bench-musl" { } ''
    b c-gcc-O2-static-musl   $CC -O2 -static -o $out/c-gcc-O2-static-musl ${src}/prog.c
    b cpp-gxx-O2-static-musl $CXX -O2 -std=c++17 -static -o $out/cpp-gxx-O2-static-musl ${src}/prog.cpp
  '';
  rustGo = build pkgs.stdenv "rea-bench-rust-go" { native = [ pkgs.rustc pkgs.go ]; } ''
    b rust-O rustc -C opt-level=3 -C debuginfo=0 -o $out/rust-O ${src}/prog.rs
    b go     go build -o $out/go ${src}/prog.go
  '';
in
pkgs.symlinkJoin { name = "rea-bench-corpus"; paths = [ glibcDyn glibcStatic musl rustGo ]; }
