"""Output layout ownership (displays.py) against a nested headless sway: live
set + revert timer, Keep persists and survives `reload`, disable/enable.
Scratch state/local/config dirs; the nested config includes the scratch include."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

from harness import PYTHON, ROOT, TMP, E2EFailure, Nested


class Env:
    def __init__(self) -> None:
        self.dir = Path(tempfile.mkdtemp(prefix="displays-", dir=TMP))
        self.state = self.dir / "state"
        self.state.mkdir()
        (self.state / "common.json").write_text(json.dumps({"version": 1}))
        (self.state / "P.json").write_text(json.dumps({"version": 1}))
        self.include = self.dir / "sway-apps.conf"
        self.include.write_text("")
        sway = os.environ.get("E2E_SWAY", "sway")
        self.vars = {
            "SWAY_APPS_E2E": "1", "SWAY_APPS_PROFILE": "P", "SWAY_APPS_GIT": "0",
            "SWAY_APPS_STATE_DIR": str(self.state), "SWAY_APPS_LOCAL_STATE_DIR": str(self.dir / "local"),
            "XDG_CONFIG_HOME": str(self.dir / "cfg"), "SWAY_APPS_INCLUDE": str(self.include),
            "SWAY_APPS_TMUX_INCLUDE": str(self.dir / "tmux.conf"), "SWAY_APPS_TMUX_RELOAD": "0",
            "SWAY_APPS_SWAY_FEATURES": "owns_outputs", "SWAY_APPS_SWAY_BIN": sway,
            "SWAY_APPS_SWAYMSG_BIN": str(Path(sway).with_name("swaymsg")) if os.sep in sway else "swaymsg",
        }

    def nested(self, outputs) -> Nested:
        return Nested(outputs=outputs, config=f"include {self.include}")

    def cli(self, s: Nested, *args: str, ok: bool = True) -> subprocess.CompletedProcess:
        r = subprocess.run([PYTHON, "-m", "sway_apps", "--json", *args], cwd=str(ROOT), env={**s.env, **self.vars},
                           capture_output=True, text=True, timeout=30)
        if ok and r.returncode != 0:
            raise E2EFailure(f"sway-apps {' '.join(args)} -> {r.returncode}: {r.stdout[-300:]} {r.stderr[-300:]}")
        return r

    def saved(self) -> dict:
        return ((json.loads((self.state / "P.json").read_text()).get("settings") or {}).get("displays") or {}).get("outputs") or {}

    def pending(self) -> Path:
        return self.dir / "local" / "displays-pending.json"


def _out(s: Nested, name: str) -> dict:
    return next(o for o in s.outputs() if o["name"] == name)


def case_displays_exact_scales_listed():
    e = Env()
    with e.nested([(1920, 1080)]) as s:
        data = json.loads(e.cli(s, "displays", "exact-scales", "HEADLESS-1").stdout)
        got = {x["scale"]: tuple(x["logical"]) for x in data["scales"]}
        if got.get(1.5) != (1280, 720) or got.get(1.25) != (1536, 864) or 1.4 in got:
            raise E2EFailure(f"exact scales {got}")
        r = e.cli(s, "displays", "set", "HEADLESS-1", "--scale", "1.4", ok=False)
        if r.returncode == 0 or "not exact" not in (r.stdout + r.stderr):
            raise E2EFailure(f"non-exact scale accepted without --force-scale: {r.stdout} {r.stderr}")


def case_displays_live_change_reverts_after_timeout():
    e = Env()
    with e.nested([(1920, 1080), (1280, 720)]) as s:
        e.cli(s, "displays", "set", "HEADLESS-1", "--scale", "1.5", "--revert-after", "2")
        s.wait(lambda: _out(s, "HEADLESS-1")["scale"] == 1.5, "scale 1.5 applied live")
        if e.saved():
            raise E2EFailure("a live-only change was persisted")
        # the CLI process is gone: only the detached guard can revert it
        s.wait(lambda: _out(s, "HEADLESS-1")["scale"] == 1.0, "reverted to 1.0 by the guard", 8)
        s.wait(lambda: not e.pending().exists(), "pending record cleared")
        if e.saved():
            raise E2EFailure("revert persisted something")


def case_displays_keep_persists_and_survives_reload():
    e = Env()
    with e.nested([(1920, 1080), (1280, 720)]) as s:
        e.cli(s, "displays", "set", "HEADLESS-2", "--pos", "0,1080", "--revert-after", "20")
        s.wait(lambda: (_out(s, "HEADLESS-2")["rect"]["x"], _out(s, "HEADLESS-2")["rect"]["y"]) == (0, 1080), "moved live")
        e.cli(s, "displays", "keep")
        sv = e.saved().get("HEADLESS-2") or {}
        if (sv.get("x"), sv.get("y")) != (0, 1080):
            raise E2EFailure(f"keep did not persist: {e.saved()}")
        if 'output "HEADLESS-2" {' not in e.include.read_text() or "position 0 1080" not in e.include.read_text():
            raise E2EFailure("include not regenerated:\n" + e.include.read_text()[-600:])
        if e.pending().exists():
            raise E2EFailure("pending record left after keep")
        time.sleep(2.5)   # the guard's deadline would have been 20 s; nothing may revert in between
        s.cmd("reload")
        s.wait(lambda: (_out(s, "HEADLESS-2")["rect"]["x"], _out(s, "HEADLESS-2")["rect"]["y"]) == (0, 1080), "position after reload")
        e.cli(s, "displays", "set", "HEADLESS-1", "--scale", "1.5", "--revert-after", "20")
        s.wait(lambda: _out(s, "HEADLESS-1")["scale"] == 1.5, "second change live")
        e.cli(s, "displays", "revert")
        s.wait(lambda: _out(s, "HEADLESS-1")["scale"] == 1.0, "explicit revert")


def case_displays_disable_enable_output():
    e = Env()
    with e.nested([(1920, 1080), (1280, 720)]) as s:
        e.cli(s, "displays", "set", "HEADLESS-2", "--disable")
        s.wait(lambda: not _out(s, "HEADLESS-2")["active"], "HEADLESS-2 disabled")
        s.cmd("reload")
        time.sleep(0.5)
        s.wait(lambda: not _out(s, "HEADLESS-2")["active"], "still disabled after reload (include)")
        r = e.cli(s, "displays", "set", "HEADLESS-1", "--disable", ok=False)
        if r.returncode == 0 or not _out(s, "HEADLESS-1")["active"]:
            raise E2EFailure("disabling the last active output was allowed")
        e.cli(s, "displays", "set", "HEADLESS-2", "--enable")
        s.wait(lambda: _out(s, "HEADLESS-2")["active"], "HEADLESS-2 enabled again")
        if not e.saved()["HEADLESS-2"]["enabled"]:
            raise E2EFailure("enable not persisted")
