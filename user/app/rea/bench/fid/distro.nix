{ pkgs, mkFid, mkLinkedFid ? null }:
# M2 extension (AINF-408): FID sets from the static libraries real third-party Linux
# binaries are linked against — Debian 12, Ubuntu 24.04 and Alpine 3.20 — taken from the
# distributions' official packages pinned by hash (the exact versions their toolchains
# shipped on 2026-10-14). nixpkgs-only sets named ~15 % of functions in binaries built
# with other library versions; these cover the common build hosts.
let
  lib = pkgs.lib;
  # Store names cannot contain "~" (Ubuntu versions): give each download a clean name.
  get = url: hash: pkgs.fetchurl { inherit url hash; name = lib.replaceStrings [ "~" ] [ "-" ] (baseNameOf url); };
  # .deb = ar(control, data.tar.{xz,zst}); .apk = concatenated gzip tar streams.
  unpack = name: srcs: pkgs.runCommand "rea-fid-src-${name}" { nativeBuildInputs = [ pkgs.binutils pkgs.zstd pkgs.xz pkgs.gnutar ]; } ''
    mkdir -p $out
    for s in ${lib.concatStringsSep " " srcs}; do
      case "$s" in
        *.deb) d=$(mktemp -d); (cd $d && ar x $s && tar -xf data.tar.* -C $out) ;;
        *.apk) tar -xzf $s -C $out 2>/dev/null || true ;;
      esac
    done
  '';
  debian12 = unpack "debian12" [
    (get "http://deb.debian.org/debian/pool/main/g/glibc/libc6-dev_2.36-9+deb12u14_amd64.deb" "sha256-Ahj8K+/NeEwbDGKSwKE3zon60FTvqlea0IO+4PLAGq4=")
    (get "http://deb.debian.org/debian/pool/main/g/gcc-12/libstdc++-12-dev_12.2.0-14+deb12u1_amd64.deb" "sha256-0o3vbCNjBDK1fLOKTC/WennU4EhAJzhspujWAFw9enM=")
    (get "http://deb.debian.org/debian/pool/main/g/gcc-12/libgcc-12-dev_12.2.0-14+deb12u1_amd64.deb" "sha256-1yAlk4CoTy/8b+UW7/XL6cigBROOjWpXSHR7pLNASoI=")
  ];
  ubuntu2404 = unpack "ubuntu2404" [
    (get "http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6-dev_2.39-0ubuntu8.9_amd64.deb" "sha256-4T1fzBsqhvdbyo4AJqjjnyT+l8qG6SvnmZH4aX6xMG8=")
    (get "http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-13/libstdc++-13-dev_13.3.0-6ubuntu2~24.04.1_amd64.deb" "sha256-7lYz6GPhnDOB7ZeELONe0y7elqPRrk6UwFHTA2/iE0c=")
    (get "http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-13/libgcc-13-dev_13.3.0-6ubuntu2~24.04.1_amd64.deb" "sha256-zWidsmke2qEPNzKTByknlrtZnnIuBQXHnhTKqh/pqTo=")
  ];
  alpine320 = unpack "alpine320" [
    (get "https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/musl-dev-1.2.5-r3.apk" "sha256-NqvPihmYJggLmypF+GeCr65K5ci4MxkJ5RE5EeK9ytE=")
    (get "https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/libstdc++-dev-13.2.1_git20240309-r1.apk" "sha256-Q92rEb104R8St0Hlx33Coa2JfVllM5jd8Z4D/JAY12I=")
    (get "https://dl-cdn.alpinelinux.org/alpine/v3.20/main/x86_64/gcc-13.2.1_git20240309-r1.apk" "sha256-88YJWQXL4x13rH47ozlwWLlSdR0N1rBRHouqRk7w+pk=")
  ];
  gnu = name: src: gccV: glibcV: let l = "${src}/usr/lib/x86_64-linux-gnu"; g = "${src}/usr/lib/gcc/x86_64-linux-gnu/${gccV}"; in [
    (mkFid { name = "${name}-glibc-${glibcV}"; family = "glibc-${name}"; version = glibcV; archives = [ "${l}/libc.a" ]; })
    (mkFid { name = "${name}-libm-${glibcV}"; family = "glibc-libm-${name}"; version = glibcV; archives = [ "${l}/libm.a" "${l}/libm-*.a" ]; })
    (mkFid { name = "${name}-libstdcxx-${gccV}"; family = "libstdc++-${name}"; version = gccV; archives = [ "${g}/libstdc++.a" ]; })
    (mkFid { name = "${name}-libgcc-${gccV}"; family = "libgcc-${name}"; version = gccV; archives = [ "${g}/libgcc.a" "${g}/libgcc_eh.a" ]; })
  ];
  # Linked variants (fid.nix mkLinkedFid): what a non-PIE `gcc -static` binary contains
  # after ld's TLS/GOT relaxations, which the per-object sets cannot match.
  gnuLinked = name: src: gccV: glibcV: let
    l = "${src}/usr/lib/x86_64-linux-gnu"; g = "${src}/usr/lib/gcc/x86_64-linux-gnu/${gccV}";
    crtPre = [ "${l}/crt1.o" "${l}/crti.o" "${g}/crtbeginT.o" ]; crtPost = [ "${g}/crtend.o" "${l}/crtn.o" ];
    base = [ "${l}/libc.a" "${g}/libgcc.a" "${g}/libgcc_eh.a" ];
    libm = [ "${l}/libm.a" "${l}/libm-${glibcV}.a" ];
  in [
    (mkLinkedFid { name = "${name}-glibc-${glibcV}-linked"; family = "glibc-${name}"; version = glibcV; syms = [ "${l}/libc.a" ]; link = base; inherit crtPre crtPost; })
    (mkLinkedFid { name = "${name}-libm-${glibcV}-linked"; family = "glibc-libm-${name}"; version = glibcV; syms = libm; link = libm ++ base; inherit crtPre crtPost; })
    (mkLinkedFid { name = "${name}-libstdcxx-${gccV}-linked"; family = "libstdc++-${name}"; version = gccV; syms = [ "${g}/libstdc++.a" ]; link = [ "${g}/libstdc++.a" ] ++ libm ++ base; inherit crtPre crtPost; })
  ];
  muslLinked = let
    l = "${alpine320}/usr/lib"; g = "${alpine320}/usr/lib/gcc/x86_64-alpine-linux-musl/13.2.1";
    crtPre = [ "${l}/crt1.o" "${l}/crti.o" "${g}/crtbeginT.o" ]; crtPost = [ "${g}/crtend.o" "${l}/crtn.o" ];
    base = [ "${l}/libc.a" "${g}/libgcc.a" "${g}/libgcc_eh.a" ];
  in [
    (mkLinkedFid { name = "alpine320-musl-1.2.5-linked"; family = "musl-alpine320"; version = "1.2.5-r3"; syms = [ "${l}/libc.a" ]; link = base; inherit crtPre crtPost; })
    (mkLinkedFid { name = "alpine320-libstdcxx-13.2.1-linked"; family = "libstdc++-alpine320"; version = "13.2.1"; syms = [ "${l}/libstdc++.a" ]; link = [ "${l}/libstdc++.a" ] ++ base; inherit crtPre crtPost; })
  ];
  linked = if mkLinkedFid == null then [ ] else
    gnuLinked "debian12" debian12 "12" "2.36" ++ gnuLinked "ubuntu2404" ubuntu2404 "13" "2.39" ++ muslLinked;
in
gnu "debian12" debian12 "12" "2.36"
++ gnu "ubuntu2404" ubuntu2404 "13" "2.39"
++ [
  (mkFid { name = "alpine320-musl-1.2.5"; family = "musl-alpine320"; version = "1.2.5-r3"; archives = [ "${alpine320}/usr/lib/libc.a" ]; })
  (mkFid { name = "alpine320-libstdcxx-13.2.1"; family = "libstdc++-alpine320"; version = "13.2.1"; variant = "x86_64-linux-musl"; archives = [ "${alpine320}/usr/lib/libstdc++.a" ]; })
  (mkFid { name = "alpine320-libgcc-13.2.1"; family = "libgcc-alpine320"; version = "13.2.1"; archives = [ "${alpine320}/usr/lib/gcc/x86_64-alpine-linux-musl/13.2.1/libgcc.a" "${alpine320}/usr/lib/gcc/x86_64-alpine-linux-musl/13.2.1/libgcc_eh.a" ]; })
]
++ linked
