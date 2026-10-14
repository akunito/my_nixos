{ pkgs, ghidra ? pkgs.ghidra }:
# M3 (AINF-408): Kuna, the Rust port of Ghidra's decompiler (Noelo-Lab/kuna, Apache-2.0),
# built from a pinned commit, as an ALTERNATIVE engine for the benchmark only — never
# REA's default. Ghidra spawns Decompiler/os/linux_x86_64/decompile and Kuna's
# kuna_ghidra speaks the same wire protocol (it gets the specs over the wire), so a
# Ghidra tree with that one file swapped runs Kuna headless. The tree is a real copy:
# Ghidra canonicalises its install path, so a symlink farm would resolve back to the
# stock binary.
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
    chmod -R u+w $out/Ghidra/Features/Decompiler/os
    install -m755 ${kuna}/bin/kuna_ghidra $out/Ghidra/Features/Decompiler/os/linux_x86_64/decompile
  '';
}
