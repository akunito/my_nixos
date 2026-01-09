{ lib
, stdenvNoCC
, fetchFromGitHub
, makeWrapper
, wrapGAppsHook3
, python3
, gtk3
, gobject-introspection
, swaybg
}:

let
  pythonEnv = python3.withPackages (ps: [
    ps.pillow
    ps.pygobject3
    ps.pycairo
  ]);
in
stdenvNoCC.mkDerivation rec {
  pname = "swaybgplus";
  version = "unstable-2026-01-09";

  src = fetchFromGitHub {
    owner = "alephpt";
    repo = "swaybgplus";
    rev = "d97bc8ca2582dd781e5b23b9f3cc2634417d33cb";
    # NOTE: fetchFromGitHub hashes the *unpacked* content (like `nix store prefetch-file --unpack`).
    hash = "sha256-/Eb0D4zeK2AbFOvSlLC+j3Dh1vOVqx9MybAuBOofsEo=";
  };

  # Needed so GI can load Gtk typelibs ("Gtk-3.0.typelib") and so GTK apps get a sane runtime env.
  buildInputs = [
    gtk3
    gobject-introspection
  ];

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsHook3
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/swaybgplus
    cp -R . $out/share/swaybgplus

    mkdir -p $out/bin

    # CLI wrapper
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/swaybgplus \
      --add-flags "$out/share/swaybgplus/swaybgplus_cli.py" \
      --prefix GI_TYPELIB_PATH : "${lib.makeSearchPath "lib/girepository-1.0" [ gtk3 gobject-introspection ]}" \
      --prefix PATH : ${lib.makeBinPath [ swaybg ]}

    # GUI wrapper
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/swaybgplus-gui \
      --add-flags "$out/share/swaybgplus/swaybgplus_gui.py" \
      --prefix GI_TYPELIB_PATH : "${lib.makeSearchPath "lib/girepository-1.0" [ gtk3 gobject-introspection ]}" \
      --prefix PATH : ${lib.makeBinPath [ swaybg ]}

    runHook postInstall
  '';

  meta = {
    description = "SwayBG+ - advanced multi-monitor background manager for Sway (GUI + CLI)";
    homepage = "https://github.com/alephpt/swaybgplus";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "swaybgplus";
  };
}


