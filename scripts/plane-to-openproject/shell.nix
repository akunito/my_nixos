{ pkgs ? import <nixpkgs> {} }:
# Dev shell for the Plane -> OpenProject demo migration.
#   nix-shell --run "python migrate.py --dry-run"
pkgs.mkShell {
  buildInputs = with pkgs; [
    (python313.withPackages (ps: with ps; [
      requests
      html2text   # HTML -> Markdown (OpenProject descriptions/wiki are markdown)
      beautifulsoup4
    ]))
  ];
}
