{ pkgs }:
# Hopper 6.4.2 Linux demo, unmodified (AINF-408 F6). REA accepts only this build: it checks
# the launcher's sha256 (LinuxHopper.ts SUPPORTED_HOPPER_SHA256 = 0294ced1…) and the demo
# helper clicks the registration dialog by pixel, so NO patchelf/strip — it runs through
# nix-ld in the guest. Demo terms: 30-minute sessions, no save/export; personal use.
pkgs.stdenvNoCC.mkDerivation {
  pname = "hopper-demo";
  version = "6.4.2";
  src = pkgs.fetchurl {
    url = "https://www.hopperapp.com:443/downloader/public/Hopper-6.4.2-Linux-demo.pkg.tar.xz";
    # SHA-1 and length pinned by REA (LinuxHopper.ts SUPPORTED_RELEASES.arch).
    sha1 = "92d780b61cab38eda95dc4112dee4fbeb0920f46";
    # The vendor answers 403 without REA's headers (measured).
    curlOptsList = [ "-H" "accept: application/json" "-A" "rea-installer" ];
  };
  dontUnpack = true;
  dontFixup = true;
  installPhase = ''
    mkdir -p $out
    tar -xJf $src -C $out opt
  '';
}
