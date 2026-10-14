{ pkgs, ghidra ? pkgs.ghidra }:
# M3 (AINF-408): Kuna, the Rust port of Ghidra's decompiler (Noelo-Lab/kuna, Apache-2.0),
# built from a pinned commit, as an ALTERNATIVE engine for the benchmark only — never
# REA's default. Ghidra spawns Decompiler/os/linux_x86_64/decompile and Kuna's
# kuna_ghidra speaks the same wire protocol (it gets the specs over the wire), so a
# Ghidra tree with that one file swapped runs Kuna headless. nixpkgs' support/launch.sh
# is a wrapProgram wrapper that execs the ORIGINAL install's .launch.sh-wrapped by
# absolute path, so a plain copy silently ran the stock decompiler (measured: identical
# output); the copy's wrapper is replaced by a script pointing at itself.
let
  kuna = pkgs.rustPlatform.buildRustPackage {
    pname = "kuna-ghidra";
    version = "1.833";
    src = pkgs.fetchFromGitHub {
      owner = "Noelo-Lab";
      repo = "kuna";
      rev = "fe01d6294eb0d1053ce343c8943646df88e143fc"; # tag v1.833
      hash = "sha256-adJONwYWLr9JjuXRbw4nms06R0v/6EyhzpfzRodlTGk=";
    };
    sourceRoot = "source/decompiler";
    cargoHash = "sha256-K33ivuxMOZQz/n3NusQyM7EV8brCzPxwEI+blrsF4GU=";
    cargoBuildFlags = [ "-p" "kuna-ghidra" ];
    doCheck = false;
  };
in
{
  inherit kuna;
  ghidraTree = pkgs.runCommand "ghidra-kuna-${kuna.version}" { } ''
    cp -r ${ghidra}/lib/ghidra $out
    chmod -R u+w $out/Ghidra/Features/Decompiler/os $out/support
    # launch.sh is a binary makeBinaryWrapper: replace it with the equivalent script.
    rm $out/support/launch.sh
    cat > $out/support/launch.sh <<EOF
    #!${pkgs.runtimeShell}
    export NIX_GHIDRAHOME=\''${NIX_GHIDRAHOME:-$out/Ghidra}
    export PATH=${pkgs.jdk21}/bin:\$PATH
    exec -a "\$0" $out/support/.launch.sh-wrapped "\$@"
    EOF
    chmod 755 $out/support/launch.sh
    install -m755 ${kuna}/bin/kuna_ghidra $out/Ghidra/Features/Decompiler/os/linux_x86_64/decompile
  '';
}
