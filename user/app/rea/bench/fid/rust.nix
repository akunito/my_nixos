{ pkgs, mkFid }:
# M2 (AINF-408): Rust std FID sets from the OFFICIAL rust-std tarballs (static.rust-lang.org,
# pinned by hash) for the recent stable releases. std is statically linked into every Rust
# binary and its hashes change with each rustc release, so a third-party binary only gets
# names from the set of its own compiler version (the version is in the binary's .comment).
let
  lib = pkgs.lib;
  hashes = {
    "1.92.0" = "sha256-XxBoBe2G6/jfKHA55TpFz5dDke9NCIwnYHdrBbjki10=";
    "1.93.0" = "sha256-qEmkGNDyfmlXPkF2PDlekkoLmMFvzcVVmcHHnCfBx3c=";
    "1.94.0" = "sha256-3TNlMQfDbgQAggUNnlR+ZNrFtFa6dAaUMNg4wAwYmgU=";
    "1.95.0" = "sha256-BH6nCYgD01APoQcunO5Tkml+IVJVWeRFgSiiv4dKo4I=";
    "1.96.0" = "sha256-wJx8ZGJI8U9HP196AprxXuV8Op+byT36ctliGThYa4I=";
    "1.97.0" = "sha256-DENhgSinprlrCwTATPeyjdUvsJkadMlhX70aaE/4hxI=";
    "1.98.0" = "sha256-9QIubJWlrSPMolE9yCgSAPWF+hiN5jcKo3sSikP4dqM=";
    "1.99.0" = "sha256-Pljf8tC3IZa16k6QU24XTUAN6IVkpSaUaGuB4JEWmTM=";
  };
  std = v: hash: let
    src = pkgs.fetchurl { url = "https://static.rust-lang.org/dist/rust-std-${v}-x86_64-unknown-linux-gnu.tar.xz"; inherit hash; };
    tree = pkgs.runCommand "rust-std-${v}-x86_64-linux" { nativeBuildInputs = [ pkgs.xz ]; } ''
      mkdir -p $out && tar -xJf ${src} -C $out --strip-components=1
    '';
    d = "${tree}/rust-std-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/lib";
  in mkFid { name = "rust-std-official-${v}"; family = "rust-std"; version = v; variant = "x86_64-unknown-linux-gnu (official)";
             archives = map (l: "${d}/lib${l}-*.rlib") [ "core" "alloc" "std" ]; };
in
lib.mapAttrsToList std hashes
