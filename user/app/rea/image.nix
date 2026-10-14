{ pkgs, rea-agents }:
# pkgs = nixpkgs-unstable (Ghidra 12.1.4, crun 1.30.1; the stable channel is older).
# REA sandbox image (AINF-408 F1). Everything from nixpkgs-unstable with absolute
# store paths: REA's defaults (/usr/bin/prlimit…) do not exist on NixOS.
let
  ghidra = pkgs.ghidra;          # 12.1.4 — REA requires 12.1.x
  # Extensions (mejoras.md M0, audited 2026-10-14). NOT via GHIDRA_INSTALL_DIR:
  # withExtensions is a symlinkJoin holding only Extensions/ + wrappers, and REA
  # requires support/analyzeHeadless, application.properties and the native
  # decompiler under the install dir. nixpkgs' Ghidra patch reads NIX_GHIDRAHOME as
  # an extra root, and REA forwards the whole environment to the JVM it launches.
  # wasm is broken for 12.1.4 in nixpkgs; kaiju changes every disassembly and waits
  # for the M1 benchmark.
  ghidraExt = pkgs.ghidra.withExtensions (e: [ e.ghidra-golanganalyzerextension e.findcrypt ]);
  jdk = pkgs.jdk21;
  py = pkgs.python3.withPackages (ps: [ ps.pwntools ]);
  tools = with pkgs; [
    bashInteractive coreutils findutils gnugrep gnused gawk procps util-linux file
    ghidra jdk rea-agents nodejs_24
    binutils rizin wireshark-cli wabt mitmproxy apktool ilspycmd binwalk unblob
    detect-it-easy upx yara py
  ];
  nss = pkgs.dockerTools.fakeNss.override {
    extraPasswdLines = [ "rea:x:1000:100:rea:/tmp:/bin/sh" ];
    extraGroupLines = [ "users:x:100:" ];
  };
  bin = p: "${p}/bin";
in
pkgs.dockerTools.buildLayeredImage {
  name = "rea-sandbox";
  tag = null; # content hash: a new build never reuses a loaded tag
  contents = tools ++ [ nss pkgs.dockerTools.binSh ];
  config = {
    User = "1000:100";
    Entrypoint = [ "${rea-agents}/bin/rea" ];
    Env = [
      "PATH=${pkgs.lib.makeBinPath tools}"
      "GHIDRA_INSTALL_DIR=${ghidra}/lib/ghidra"
      "JAVA_HOME=${jdk}"
      "GHIDRA_HEADLESS_MAXMEM=4G"
      "NIX_GHIDRAHOME=${ghidraExt}/lib/ghidra/Ghidra"
      "REA_TSHARK_COMMAND=${bin pkgs.wireshark-cli}/tshark"
      "REA_CAPINFOS_COMMAND=${bin pkgs.wireshark-cli}/capinfos"
      "REA_TSHARK_PRLIMIT_COMMAND=${bin pkgs.util-linux}/prlimit"
      "REA_SIGROK_PRLIMIT_COMMAND=${bin pkgs.util-linux}/prlimit"
      "REA_EVM_PRLIMIT_COMMAND=${bin pkgs.util-linux}/prlimit"
      "REA_JAVASCRIPT_PRLIMIT_COMMAND=${bin pkgs.util-linux}/prlimit"
      "REA_FIRMWARE_PRLIMIT_COMMAND=${bin pkgs.util-linux}/prlimit"
      "REA_PWNTOOLS_PYTHON=${py}/bin/python3"
      "REA_WABT_BIN_DIRECTORY=${bin pkgs.wabt}"
      "REA_BINWALK_COMMAND=${bin pkgs.binwalk}/binwalk"
      "REA_UNBLOB_COMMAND=${bin pkgs.unblob}/unblob"
      "REA_MITMDUMP_COMMAND=${bin pkgs.mitmproxy}/mitmdump"
      "REA_RIZIN_COMMAND=${bin pkgs.rizin}/rizin"
      "REA_OBJDUMP=${bin pkgs.binutils}/objdump"
      "REA_ILSPY_CMD_PATH=${bin pkgs.ilspycmd}/ilspycmd"
      "REA_APKTOOL_COMMAND=${bin pkgs.apktool}/apktool"
      "NODE_ENV=production"
    ];
  };
}
