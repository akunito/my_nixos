"""Keypad GUI page (SWAY-18) inside a nested sway, on a scratch copy of keyd-devices.json."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from harness import PYTHON, ROOT, E2EFailure, Nested

HERE = Path(__file__).resolve().parent


def case_keypad_gui_page():
    with Nested(outputs=[(1280, 1000)]) as s:
        state = s.dir / "state"
        state.mkdir()
        shutil.copy(ROOT.parent / "apps" / "keyd-devices.json", state / "keyd-devices.json")
        env = {**s.env, "SWAY_APPS_STATE_DIR": str(state), "SWAY_APPS_GIT": "0", "PYTHONPATH": os.pathsep.join(p for p in (str(ROOT), s.env.get("PYTHONPATH", "")) if p)}
        r = subprocess.run([PYTHON, "-W", "ignore::DeprecationWarning", str(HERE / "gui_keypad_check.py")],
                           env=env, capture_output=True, text=True, timeout=90)
        bad = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode or bad:
            raise E2EFailure("gui: " + " | ".join(bad) + " " + r.stderr[-1500:].replace("\n", " / "))
