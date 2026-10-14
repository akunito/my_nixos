{ pkgs, rea-agents, pwndbg ? null, ghidraExtensions ? [ ] }:
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
  # ghidraExtensions: our own modules, e.g. the M2 Function ID set (bench/fid).
  ghidraExt = pkgs.ghidra.withExtensions (e: [ e.ghidra-golanganalyzerextension e.findcrypt ] ++ ghidraExtensions);
  jdk = pkgs.jdk21;
  # The recorded-crash decoder (inspect_recorded_crash) requires pyelftools 0.33 exactly
  # ("Expected pyelftools 0.33", measured; nixpkgs has 0.32). The same profile pins
  # unicorn 2.1.2 (layout_impl.py: pwntools@4.15.0;pyelftools@0.33;
  # unicorn@2.1.2); the Python binding builds from the C library's own source.
  unicorn = pkgs.unicorn.overrideAttrs (_: {
    version = "2.1.2";
    src = pkgs.fetchFromGitHub {
      owner = "unicorn-engine"; repo = "unicorn"; rev = "2.1.2";
      hash = "sha256-qA84xBztyWmt/rUExhhZMkQzvDPx0UE9MAIPG/Su3iE=";
    };
  });
  python = pkgs.python3.override {
    packageOverrides = _: super: {
      # 2.1.2's bindings build with versioningit (nixpkgs' recipe targets 2.1.4).
      unicorn = (super.unicorn.override { inherit unicorn; }).overridePythonAttrs (o: {
        build-system = (o.build-system or [ ]) ++ [ super.versioningit ];
        # versioningit wants git or an sdist PKG-INFO; give it the latter.
        postPatch = (o.postPatch or "") + "printf 'Metadata-Version: 2.1\\nName: unicorn\\nVersion: 2.1.2\\n' > PKG-INFO\n";
      });
      pyelftools = super.pyelftools.overridePythonAttrs (_: {
        version = "0.33";
        src = pkgs.fetchFromGitHub {
          owner = "eliben"; repo = "pyelftools"; rev = "v0.33";
          hash = "sha256-NqF5A6PRl4uncwNS9j44fIV7ovlljiucvV2Msv0LK/w=";
        };
        doCheck = false;
      });
    };
  };
  py = python.withPackages (ps: [ ps.pwntools ]);
  bin = p: "${p}/bin";
  # REA checks exact banners: WABT 1.0.42 (wasmArtifact.ts), sigrok-cli 0.7.2
  # (SigrokRecordingProvider.ts); nixpkgs has 1.0.41 and 0.8.0-unstable.
  wabt = pkgs.wabt.overrideAttrs (_: {
    version = "1.0.42";
    src = pkgs.fetchFromGitHub {
      owner = "WebAssembly"; repo = "wabt"; rev = "1.0.42"; fetchSubmodules = true;
      hash = "sha256-33XpYt42Jw2xfwBR64jVI3VYVIKD1YjND9SSI6CdkaM=";
    };
  });
  sigrok-cli = pkgs.sigrok-cli.overrideAttrs (_: {
    version = "0.7.2";
    src = pkgs.fetchurl {
      url = "https://sigrok.org/download/source/sigrok-cli/sigrok-cli-0.7.2.tar.gz";
      hash = "sha256-cdBEPzaJe/Vlcy3sIGgw2+oPJ4m2YBzxBTayhtEUCrg=";
    };
  });
  # The JAR REA's own JadxRelease.ts pins (version, URL and sha256 copied verbatim).
  jadxMcpJar = pkgs.fetchurl {
    url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar";
    sha256 = "6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75";
  };
  # Official release binary (docs/javascript-recovery.md: "the same one CI verifies").
  wakaru = pkgs.stdenv.mkDerivation {
    pname = "wakaru"; version = "1.14.0";
    src = pkgs.fetchurl {
      url = "https://github.com/pionxzh/wakaru/releases/download/v1.14.0/wakaru-linux-x64.tar.gz";
      hash = "sha256-2w5iADRyMZWrQm6U0A1V29j9AQapKK2iVj8RAxltCfo=";
    };
    sourceRoot = ".";
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    dontStrip = true; # bun/single-file executables carry their payload after the ELF
    installPhase = "install -Dm755 wakaru $out/bin/wakaru";
  };
in
rec {
  tools = with pkgs; [
    bashInteractive coreutils findutils gnugrep gnused gawk procps util-linux file
    ghidra jdk rea-agents nodejs_24
    binutils rizin wireshark-cli wabt mitmproxy apktool ilspycmd binwalk unblob
    detect-it-easy upx yara osslsigncode py gdb android-tools sigrok-cli wakaru
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
    REA_WABT_BIN_DIRECTORY = bin wabt;
    REA_BINWALK_COMMAND = "${bin pkgs.binwalk}/binwalk";
    REA_UNBLOB_COMMAND = "${bin pkgs.unblob}/unblob";
    REA_MITMDUMP_COMMAND = "${bin pkgs.mitmproxy}/mitmdump";
    REA_RIZIN_COMMAND = "${bin pkgs.rizin}/rizin";
    REA_OBJDUMP_COMMAND = "${bin pkgs.binutils}/objdump";
    REA_GDB_COMMAND = "${bin pkgs.gdb}/gdb";
    REA_ADB_PATH = "${bin pkgs.android-tools}/adb";
    REA_JADX_MCP_JAR = "${jadxMcpJar}";
    REA_SIGROK_COMMAND = "${bin sigrok-cli}/sigrok-cli";
    REA_WAKARU_COMMAND = "${bin wakaru}/wakaru";
  } // pkgs.lib.optionalAttrs (pwndbg != null) {
    # pwndbg's own venv (uv2nix, its frozen uv.lock) with its gdb; REA runs gdbinit.py
    # from it with PWNDBG_NO_AUTOUPDATE=1, core-only (PwndbgCoreContext.ts).
    REA_PWNDBG_GDB = "${pwndbg}/bin/gdb";
    REA_PWNDBG_GDBINIT = "${pwndbg}/share/pwndbg/gdbinit.py";
    REA_PWNDBG_VENV_PATH = "${pwndbg}";
    REA_ILSPY_CMD_PATH = "${bin pkgs.ilspycmd}/ilspycmd";
    REA_APKTOOL_COMMAND = "${bin pkgs.apktool}/apktool";
    NODE_ENV = "production";
  };
}
