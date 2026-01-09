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

    # #region agent log
    # DEBUG wrapper: logs startup + failure reasons to repo-local NDJSON.
    # This is temporary instrumentation for Cursor debug mode.
    cat > $out/share/swaybgplus/_agent_gui_wrapper.py <<'PY'
import json, os, runpy, shutil, sys, time, traceback

LOG_PATH = "/home/akunito/.dotfiles/.cursor/debug.log"

def _log(hypothesisId, location, message, data=None):
    try:
        payload = {
            "sessionId": "debug-session",
            "runId": os.environ.get("SWAYBGPLUS_RUNID", "run1"),
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data or {},
            "timestamp": int(time.time() * 1000),
        }
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except Exception:
        pass

def main():
    _log("B", "_agent_gui_wrapper.py:main", "launcher entry", {
        "argv": sys.argv[:],
        "cwd": os.getcwd(),
        "env": {k: os.environ.get(k, "") for k in [
            "WAYLAND_DISPLAY","DISPLAY","SWAYSOCK","XDG_RUNTIME_DIR","XDG_CURRENT_DESKTOP","XDG_SESSION_TYPE",
            "GDK_BACKEND","XDG_CONFIG_HOME","HOME","GI_TYPELIB_PATH"
        ]},
    })

    _log("C", "_agent_gui_wrapper.py:main", "external commands", {
        "swaybg": shutil.which("swaybg"),
        "swaymsg": shutil.which("swaymsg"),
        "sway": shutil.which("sway"),
    })

    try:
        import gi  # noqa: F401
        _log("A", "_agent_gui_wrapper.py:main", "import gi ok")
        from gi.repository import Gtk  # noqa: F401
        _log("A", "_agent_gui_wrapper.py:main", "import Gtk ok")
    except Exception as e:
        _log("A", "_agent_gui_wrapper.py:main", "GTK import failed", {
            "err": repr(e),
            "tb": traceback.format_exc(limit=50),
            "sys_path_head": sys.path[:10],
        })
        raise

    try:
        gui_path = os.path.join(os.path.dirname(__file__), "swaybgplus_gui.py")
        _log("D", "_agent_gui_wrapper.py:main", "running GUI", {"gui_path": gui_path})
        runpy.run_path(gui_path, run_name="__main__")
        _log("D", "_agent_gui_wrapper.py:main", "GUI exited normally")
    except SystemExit as e:
        _log("D", "_agent_gui_wrapper.py:main", "SystemExit", {"code": getattr(e, "code", None)})
        raise
    except Exception as e:
        _log("D", "_agent_gui_wrapper.py:main", "GUI crashed", {
            "err": repr(e),
            "tb": traceback.format_exc(limit=80),
        })
        raise

if __name__ == "__main__":
    main()
PY
    # #endregion agent log

    mkdir -p $out/bin

    # CLI wrapper
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/swaybgplus \
      --add-flags "$out/share/swaybgplus/swaybgplus_cli.py" \
      --prefix GI_TYPELIB_PATH : "${lib.makeSearchPath "lib/girepository-1.0" [ gtk3 gobject-introspection ]}" \
      --prefix PATH : ${lib.makeBinPath [ swaybg ]}

    # GUI wrapper
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/swaybgplus-gui \
      --add-flags "$out/share/swaybgplus/_agent_gui_wrapper.py" \
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


