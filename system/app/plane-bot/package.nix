# The plane-bot package: python daemon + shared tgcommon, unit tests in checkPhase.
# Build alone with:
#   nix build --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in pkgs.callPackage ./system/app/plane-bot/package.nix {}'
{ lib, stdenvNoCC, makeWrapper, python3 }:

stdenvNoCC.mkDerivation {
  pname = "plane-bot";
  version = "0.1";
  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [ ./. ../tgcommon.py ];
  };
  nativeBuildInputs = [ makeWrapper python3 ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    (cd plane-bot/tests && PYTHONPATH=..:../.. python3 -m unittest discover -s . -v)
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/plane-bot $out/bin
    cp plane-bot/*.py tgcommon.py $out/lib/plane-bot/
    makeWrapper ${python3}/bin/python3 $out/bin/plane-bot \
      --add-flags "$out/lib/plane-bot/plane_bot.py" \
      --set PYTHONPATH "$out/lib/plane-bot"
    runHook postInstall
  '';
}
