{ pkgs, rea-agents }:
# One tool list + environment for both REA sandboxes (AINF-408): the OCI image
# (tier 0, rootless + krun) and the microVM guest (tiers 1-2). pkgs = nixpkgs-unstable
# (Ghidra 12.1.4 — REA requires 12.1.x; the stable channel is older).
# Every REA_* path is absolute: REA's defaults (/usr/bin/prlimit…) do not exist on NixOS.
let
  ghidra = pkgs.ghidra;
  # Extensions (mejoras.md M0, audited 2026-10-14). NOT via GHIDRA_INSTALL_DIR:
  # withExtensions is a symlinkJoin holding only Extensions/ + wrappers, and REA
  # requires support/analyzeHeadless, application.properties and the native
  # decompiler under the install dir. nixpkgs' Ghidra patch reads NIX_GHIDRAHOME as
  # an extra root, and REA forwards the whole environment to the JVM it launches.
  # An EMPTY NIX_GHIDRAHOME does not disable them. wasm is broken for 12.1.4 in
  # nixpkgs; kaiju changes every disassembly and waits for the M1 benchmark.
  ghidraExt = pkgs.ghidra.withExtensions (e: [ e.ghidra-golanganalyzerextension e.findcrypt ]);
  jdk = pkgs.jdk21;
  py = pkgs.python3.withPackages (ps: [ ps.pwntools ]);
  bin = p: "${p}/bin";
in
rec {
  tools = with pkgs; [
    bashInteractive coreutils findutils gnugrep gnused gawk procps util-linux file
    ghidra jdk rea-agents nodejs_24
    binutils rizin wireshark-cli wabt mitmproxy apktool ilspycmd binwalk unblob
    detect-it-easy upx yara osslsigncode py
  ];
  env = {
    PATH = pkgs.lib.makeBinPath tools;
    GHIDRA_INSTALL_DIR = "${ghidra}/lib/ghidra";
    JAVA_HOME = "${jdk}";
    GHIDRA_HEADLESS_MAXMEM = "4G";
    NIX_GHIDRAHOME = "${ghidraExt}/lib/ghidra/Ghidra";
    REA_TSHARK_COMMAND = "${bin pkgs.wireshark-cli}/tshark";
    REA_CAPINFOS_COMMAND = "${bin pkgs.wireshark-cli}/capinfos";
    REA_TSHARK_PRLIMIT_COMMAND = "${bin pkgs.util-linux}/prlimit";
    REA_SIGROK_PRLIMIT_COMMAND = "${bin pkgs.util-linux}/prlimit";
    REA_EVM_PRLIMIT_COMMAND = "${bin pkgs.util-linux}/prlimit";
    REA_JAVASCRIPT_PRLIMIT_COMMAND = "${bin pkgs.util-linux}/prlimit";
    REA_FIRMWARE_PRLIMIT_COMMAND = "${bin pkgs.util-linux}/prlimit";
    REA_PWNTOOLS_PYTHON = "${py}/bin/python3";
    REA_WABT_BIN_DIRECTORY = bin pkgs.wabt;
    REA_BINWALK_COMMAND = "${bin pkgs.binwalk}/binwalk";
    REA_UNBLOB_COMMAND = "${bin pkgs.unblob}/unblob";
    REA_MITMDUMP_COMMAND = "${bin pkgs.mitmproxy}/mitmdump";
    REA_RIZIN_COMMAND = "${bin pkgs.rizin}/rizin";
    REA_OBJDUMP = "${bin pkgs.binutils}/objdump";
    REA_ILSPY_CMD_PATH = "${bin pkgs.ilspycmd}/ilspycmd";
    REA_APKTOOL_COMMAND = "${bin pkgs.apktool}/apktool";
    NODE_ENV = "production";
  };
}
