# nix-ld — run pre-built, dynamically linked Linux binaries on NixOS.
#
# NixOS has no /lib64/ld-linux-x86-64.so.2; it ships a stub there whose only job
# is to print "NixOS cannot run dynamically linked executables intended for
# generic linux environments out of the box" (environment.stub-ld). nix-ld
# replaces that stub with a real loader that resolves libraries from
# programs.nix-ld.libraries.
#
# WHY IT IS NEEDED HERE: VS Code extensions download their own binaries. The
# Claude Code extension ships resources/native-binary/claude and refuses to
# start without it — that was the wall on Aga's LAPTOP_A (2026-09-18), and it is
# the same story for most language servers. On a machine where someone installs
# extensions from the marketplace, this is the difference between "it works" and
# "an error nobody can act on".
#
# Flag: nixLdEnable. Extra libraries: nixLdExtraLibraries (list of packages).

{ config, lib, pkgs, systemSettings, ... }:

lib.mkIf (systemSettings.nixLdEnable or false) {
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries =
    (with pkgs; [
      stdenv.cc.cc.lib # libstdc++, libgcc_s — the usual missing pair
      zlib
      openssl
      curl
      glib
      libgcc
    ])
    ++ (systemSettings.nixLdExtraLibraries or [ ]);
}
