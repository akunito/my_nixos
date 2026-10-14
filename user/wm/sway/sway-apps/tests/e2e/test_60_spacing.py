"""Spacing (sway gaps) against a nested headless sway: measured pixels, not config text."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

from harness import PYTHON, ROOT, SWAY, E2EFailure, Nested


def _cli(s: Nested, base: Path, *args: str) -> dict:
    env = {**s.env, "SWAY_APPS_STATE_DIR": str(base / "state"), "SWAY_APPS_LOCAL_STATE_DIR": str(base / "local"),
           "XDG_CONFIG_HOME": str(base / "xdg"), "SWAY_APPS_PROFILE": "E2E", "SWAY_APPS_GIT": "0", "SWAY_APPS_E2E": "1",
           "SWAY_APPS_INCLUDE": str(base / "include.conf"), "SWAY_APPS_SWAY_BIN": SWAY,
           "SWAY_APPS_SWAYMSG_BIN": str(Path(SWAY).parent / "swaymsg"), "PYTHONPATH": str(ROOT), "SWAY_APPS_TMUX_RELOAD": "0",
           "SWAY_APPS_TMUX_INCLUDE": str(base / "tmux.conf")}
    r = subprocess.run([PYTHON, "-m", "sway_apps", "--json", *args], env=env, cwd=str(ROOT), capture_output=True, text=True,
                       timeout=30)
    if r.returncode != 0:
        raise E2EFailure(f"sway-apps {' '.join(args)}: {r.stdout[-300:]} {r.stderr[-300:]}")
    return json.loads(r.stdout)


def case_gaps_inner_and_edge_live():
    with Nested(outputs=[(1280, 720)], config="gaps inner 8") as s:
        base = s.dir / "sa"
        for d in ("state", "local", "xdg"):
            (base / d).mkdir(parents=True, exist_ok=True)
        (base / "state" / "common.json").write_text('{"version": 1}')
        (base / "state" / "E2E.json").write_text('{"version": 1}')
        a = s.client("e2e.a")
        b = s.client("e2e.b")
        s.wait(lambda: a.rect()["width"] < 700, "two tiles side by side")
        res = _cli(s, base, "spacing", "set", "--inner", "4", "--edge", "2", "--no-git")
        if not res.get("gaps_live"):
            raise E2EFailure(f"gaps not applied live: {res}")

        def measured():
            ra, rb = a.rect(), b.rect()
            left, right = sorted((ra, rb), key=lambda r: r["x"])
            return left["x"], right["x"] - (left["x"] + left["width"]), left["y"]
        s.wait(lambda: measured() == (2, 4, 2), f"edge 2 / between 4 (got {measured()})")
        inc = (base / "include.conf").read_text()
        if "gaps inner 4" not in inc or "gaps outer -2" not in inc:
            raise E2EFailure("include lacks the gaps lines")
        if "between tiles 4" not in subprocess.run(
                [PYTHON, "-m", "sway_apps", "spacing", "show"], cwd=str(ROOT), capture_output=True, text=True,
                env={**s.env, "SWAY_APPS_STATE_DIR": str(base / "state"), "SWAY_APPS_PROFILE": "E2E",
                     "SWAY_APPS_LOCAL_STATE_DIR": str(base / "local"), "XDG_CONFIG_HOME": str(base / "xdg"),
                     "PYTHONPATH": str(ROOT)}).stdout:
            raise E2EFailure("show does not report the saved value")
