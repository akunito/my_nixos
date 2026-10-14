"""The harness itself: nested sway, clients, input, capture, private D-Bus."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from harness import HERE, PYTHON, E2EFailure, Nested


def case_two_outputs_and_a_client():
    with Nested(outputs=[(1280, 720), (1024, 600)]) as s:
        outs = sorted((o["name"], o["rect"]["width"]) for o in s.outputs())
        if outs != [("HEADLESS-1", 1280), ("HEADLESS-2", 1024)]:
            raise E2EFailure(f"outputs {outs}")
        a = s.client("e2e.a")
        if a.node()["type"] != "con":
            raise E2EFailure("tiled client expected")


def case_virtual_pointer_click_reaches_client():
    with Nested(outputs=1) as s:
        a = s.client("e2e.a", size="400x300", floating=True)
        a.cmd("move position 100 100")
        s.wait(lambda: a.rect()["x"] == 100, "float moved")
        s.click(200, 200)
        s.wait(lambda: "press 1" in a.log_text() and "release 1" in a.log_text(), "click logged by e2e.a")


def case_press_hold_release():
    with Nested(outputs=1) as s:
        a = s.client("e2e.a", size="400x300", floating=True)
        a.cmd("move position 100 100")
        s.wait(lambda: a.rect()["x"] == 100, "float moved")
        s.press(200, 200)
        s.wait(lambda: "press 1" in a.log_text(), "press logged")
        if "release" in a.log_text():
            raise E2EFailure("released too early")
        s.release()
        s.wait(lambda: "release 1" in a.log_text(), "release logged")


def case_second_output_absolute_coords():
    with Nested(outputs=[(1280, 720), (1024, 600)]) as s:
        s.cmd("focus output HEADLESS-2")
        b = s.client("e2e.b", size="300x200", floating=True)
        b.cmd("move absolute position 1400 100")
        s.wait(lambda: b.rect()["x"] == 1400, "float moved to output 2")
        s.click(1450, 150)
        s.wait(lambda: "press 1" in b.log_text(), "click on output 2 reached e2e.b")


def case_grab_screenshot():
    with Nested(outputs=1) as s:
        p = s.grab("full")
        if p.stat().st_size < 1000:
            raise E2EFailure("screenshot too small")


def case_tray_watcher_private_dbus():
    if os.environ.get("E2E_IN_DBUS") != "1":
        raise E2EFailure("needs the private bus the runner sets up")
    import tempfile
    env = {**os.environ, "E2E_RUNTIME": tempfile.mkdtemp(prefix="tray-", dir=os.environ.get("E2E_TMP"))}
    r = subprocess.run([PYTHON, "-W", "ignore::DeprecationWarning", str(HERE / "tray_dbus_check.py")], env=env,
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise E2EFailure("tray watcher: " + " | ".join(l for l in r.stdout.splitlines() if l.startswith("FAIL")) or r.stderr[-400:])
