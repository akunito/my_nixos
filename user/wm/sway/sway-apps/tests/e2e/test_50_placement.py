"""Placement (SWAY-10/11/12) against a nested headless sway with the real watch
daemon: journal restore after relaunch, bring off-screen, bring-all toggle,
power-off move + restore, ignore, every output off. Hotkeys go through real
`nop sway-apps …` mouse bindings, so the binding-event path is what is tested.
State, local state and XDG_CONFIG_HOME are scratch dirs: nothing touches the
repo state or ~/.config."""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

from harness import HERE, PYTHON, ROOT, SWAY, E2EFailure, Nested, walk

BINDINGS = "\n".join([
    "workspace_auto_back_and_forth yes",  # as on DESK: every move must survive it
    "bindsym --whole-window button3 nop sway-apps bring offscreen",
    "bindsym --whole-window button2 nop sway-apps bring all",
])
OUTS = [(1280, 720), (1024, 600)]  # HEADLESS-1 at x 0, HEADLESS-2 at x 1280


class Env:
    def __init__(self, s: Nested, placement: dict | None = None, roles=("main", "second")) -> None:
        self.s = s
        base = s.dir / "sa"
        self.state, self.local, self.xdg = base / "state", base / "local", base / "xdg"
        for d in (self.state, self.local, self.xdg):
            d.mkdir(parents=True, exist_ok=True)
        mons = [{"id": r, "criteria": f"HEADLESS-{i}", "group": i, "name": r} for i, r in enumerate(roles, start=1)]
        (self.state / "common.json").write_text(json.dumps({"version": 1}))
        (self.state / "E2E.json").write_text(json.dumps({"version": 1, "monitors": mons, "settings": {"placement": placement or {}}}))
        self.env = {"SWAY_APPS_STATE_DIR": str(self.state), "SWAY_APPS_LOCAL_STATE_DIR": str(self.local),
                    "XDG_CONFIG_HOME": str(self.xdg), "SWAY_APPS_PROFILE": "E2E", "SWAY_APPS_GIT": "0", "SWAY_APPS_E2E": "1",
                    "SWAY_APPS_SWAY_BIN": SWAY, "SWAY_APPS_SWAYMSG_BIN": str(Path(SWAY).parent / "swaymsg"),
                    "PYTHONPATH": str(ROOT), "SWAY_APPS_TMUX_RELOAD": "0"}
        self.daemon = None

    @property
    def log(self) -> str:
        try:
            return (self.local / "sway-apps.log").read_text()
        except FileNotFoundError:
            return ""

    def start(self) -> "Env":
        self.daemon = self.s.spawn([PYTHON, "-m", "sway_apps", "watch"], env=self.env, cwd=str(ROOT),
                                   stdout=subprocess.DEVNULL, stderr=open(self.s.dir / "watch.err", "w"))
        self.s.wait(lambda: "watching" in self.log, "watch daemon subscribed", 10)
        return self

    def cli(self, *args: str) -> dict | list:
        r = subprocess.run([PYTHON, "-m", "sway_apps", "--json", *args], env={**self.s.env, **self.env}, cwd=str(ROOT),
                           capture_output=True, text=True, timeout=20)
        if r.returncode != 0:
            raise E2EFailure(f"sway-apps {' '.join(args)}: {r.stdout[-300:]} {r.stderr[-300:]}")
        return json.loads(r.stdout)

    def journal(self) -> dict:
        try:
            return json.loads((self.local / "placement-journal.json").read_text())["records"]
        except (FileNotFoundError, ValueError, KeyError):
            return {}

    def loans(self) -> list:
        try:
            return json.loads((self.local / "placement-loans.json").read_text())["loans"]
        except (FileNotFoundError, ValueError, KeyError):
            return []


def find(s: Nested, app_id: str) -> tuple[dict, str, str] | None:
    """(node, workspace, output) of the window with this app_id."""
    for o in s.tree().get("nodes", []):
        for ws in o.get("nodes", []):
            for n in walk(ws):
                if n.get("app_id") == app_id:
                    return n, ws.get("name"), o.get("name")
    return None


def where(s: Nested, app_id: str) -> tuple[str, bool, tuple[int, int, int, int]]:
    n, ws, _ = find(s, app_id)
    r = n["rect"]
    return ws, n["type"] == "floating_con", (r["x"], r["y"], r["width"], r["height"])


def want(s: Nested, app_id: str, expected: tuple, what: str, timeout: float = 5) -> None:
    try:
        s.wait(lambda: where(s, app_id) == expected, what, timeout)
    except E2EFailure:
        raise E2EFailure(f"{what}: {app_id} is {where(s, app_id) if find(s, app_id) else 'gone'}, want {expected}")


def place(s: Nested, app_id: str, cmd: str, expected: tuple) -> None:
    """Run cmd on the window until it sticks: a just-mapped GTK window may commit
    at its first (tiled) size after the command, and sway adopts that size for
    a floating con (the same race Tracker._verify answers)."""
    n, _, _ = find(s, app_id)
    for _ in range(8):
        s.cmd(f"[con_id={n['id']}] {cmd}")
        try:
            s.wait(lambda: where(s, app_id) == expected, "placed", 0.4)
            stays(s, lambda: where(s, app_id) == expected, "drifted", 0.6)
            return
        except E2EFailure:
            pass
    raise E2EFailure(f"{app_id} never reached {expected}: {where(s, app_id)}")


def launch(s: Nested, app_id: str, size: str = "400x300") -> subprocess.Popen:
    """Like Nested.client, without insisting the window is visible (a restored
    one may land on a hidden workspace)."""
    p = s.spawn([PYTHON, str(HERE / "client.py"), "--app-id", app_id, "--size", size], stdout=subprocess.DEVNULL,
                stderr=open(s.dir / f"{app_id}.err", "a"))
    s.wait(lambda: find(s, app_id), f"{app_id} mapped", 10)
    return p


def close(s: Nested, p: subprocess.Popen, app_id: str) -> None:
    p.terminate()
    p.wait(5)
    s.wait(lambda: find(s, app_id) is None, f"{app_id} gone")


def focus_ws(s: Nested, output: str, ws: str) -> None:
    s.cmd(f"focus output {output}; workspace --no-auto-back-and-forth {ws}")


def click_on(s: Nested, app_id: str, button: str) -> None:
    n, _, _ = find(s, app_id)
    s.cmd(f"[con_id={n['id']}] focus")  # a --whole-window binding eats the click: it focuses nothing
    r = n["rect"]
    s.click(r["x"] + r["width"] // 2, r["y"] + r["height"] // 2, button)


def stays(s: Nested, pred, what: str, seconds: float) -> None:
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if not pred():
            raise E2EFailure(what)
        time.sleep(0.05)


def layout(s: Nested) -> None:
    """ws 11 on HEADLESS-1 (focused), ws 21 visible + 22 hidden on HEADLESS-2."""
    focus_ws(s, "HEADLESS-2", "22")
    launch(s, "e2e.h22")
    focus_ws(s, "HEADLESS-2", "21")
    focus_ws(s, "HEADLESS-1", "11")


# --------------------------------------------------------------------------

def case_journal_restores_workspace_floating_and_rect():
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s).start()
        layout(s)
        p = launch(s, "e2e.p")
        if e.journal():
            raise E2EFailure("first sighting must not write the journal")
        # floating on the HIDDEN ws 22 of HEADLESS-2: position first, then the move (measured order)
        place(s, "e2e.p", "floating enable, resize set 420 260, move absolute position 1400 100, "
              "move --no-auto-back-and-forth container to workspace 22", ("22", True, (1400, 100, 420, 260)))
        s.wait(lambda: (e.journal().get("e2e.p") or {}).get("rect") == [120, 100, 420, 260], "journal written (debounced)")
        rec = e.journal()["e2e.p"]
        if (rec["workspace"], rec["floating"], rec["output"]) != ("22", True, "second"):
            raise E2EFailure(f"journal {rec}")
        close(s, p, "e2e.p")
        focus_ws(s, "HEADLESS-1", "11")
        launch(s, "e2e.p")
        want(s, "e2e.p", ("22", True, (1400, 100, 420, 260)), "relaunch restored ws 22, floating, rect")
        rows = e.cli("placement", "journal", "list")
        if [r["app"] for r in rows] != ["e2e.p"]:
            raise E2EFailure(f"journal list {rows}")
        e.cli("placement", "journal", "forget", "e2e.p")
        if "e2e.p" in e.journal():
            raise E2EFailure("forget did not stick")


def case_bring_offscreen_hotkey():
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s).start()
        focus_ws(s, "HEADLESS-1", "11")
        launch(s, "e2e.t")
        launch(s, "e2e.lost")
        launch(s, "e2e.edge")
        place(s, "e2e.lost", "floating enable, resize set 300 200, move absolute position 2290 100", ("1", True, (2290, 100, 300, 200)))  # 14 px on HEADLESS-2
        place(s, "e2e.edge", "floating enable, resize set 300 200, move absolute position 2280 300", ("1", True, (2280, 300, 300, 200)))  # 24 px: reachable
        click_on(s, "e2e.t", "right")
        want(s, "e2e.lost", ("11", True, (980, 100, 300, 200)), "off-screen float brought into HEADLESS-1, size kept")
        if where(s, "e2e.edge")[2] != (2280, 300, 300, 200):
            raise E2EFailure(f"reachable float moved: {where(s, 'e2e.edge')}")
        if "bring offscreen" not in e.log:
            raise E2EFailure("verb not handled by the daemon")


def case_bring_all_toggle_there_and_back():
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s).start()
        layout(s)
        focus_ws(s, "HEADLESS-2", "21")
        launch(s, "e2e.tile")
        launch(s, "e2e.flo")
        launch(s, "e2e.moved")
        place(s, "e2e.flo", "floating enable, resize set 300 200, move absolute position 1500 150", ("21", True, (1500, 150, 300, 200)))
        focus_ws(s, "HEADLESS-1", "11")
        launch(s, "e2e.here")
        click_on(s, "e2e.here", "middle")
        s.wait(lambda: all(find(s, a)[1] == "11" for a in ("e2e.tile", "e2e.flo", "e2e.moved", "e2e.h22")), "everything lent to ws 11")
        if len(e.loans()) != 1 or len(e.loans()[0]["windows"]) != 4:
            raise E2EFailure(f"loans {e.loans()}")
        m, _, _ = find(s, "e2e.moved")
        s.cmd(f"[con_id={m['id']}] move --no-auto-back-and-forth container to workspace 12")  # the person's doing
        click_on(s, "e2e.here", "middle")
        s.wait(lambda: find(s, "e2e.tile")[1] == "21" and find(s, "e2e.h22")[1] == "22", "returned home")
        if where(s, "e2e.flo") != ("21", True, (1500, 150, 300, 200)):
            raise E2EFailure(f"float back at {where(s, 'e2e.flo')}")
        if find(s, "e2e.moved")[1] != "12":
            raise E2EFailure("a window the person moved was taken back")
        if e.loans():
            raise E2EFailure(f"loans left {e.loans()}")


def case_poweroff_move_after_grace_and_restore():
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s, {"poweroff": {"default": "move", "grace_seconds": 1.5}}).start()
        layout(s)
        focus_ws(s, "HEADLESS-2", "21")
        launch(s, "e2e.tile")
        launch(s, "e2e.flo")
        place(s, "e2e.flo", "floating enable, resize set 300 200, move absolute position 1500 150", ("21", True, (1500, 150, 300, 200)))
        focus_ws(s, "HEADLESS-1", "11")
        time.sleep(0.4)  # a coalesced read (200 ms) must have snapshotted the layout
        t0 = time.monotonic()
        s.cmd("output HEADLESS-2 disable")
        stays(s, lambda: find(s, "e2e.tile")[1] == "21", "lent before the grace ran out", 1.0)
        s.wait(lambda: find(s, "e2e.tile")[1] == "11" and find(s, "e2e.flo")[1] == "11", "lent to ws 11 after the grace", 5)
        lent_after = time.monotonic() - t0
        if lent_after < 1.4:
            raise E2EFailure(f"lent after {lent_after:.2f}s, grace is 1.5 s")
        if find(s, "e2e.h22")[1] != "11":
            raise E2EFailure("hidden ws 22's window not lent")
        s.cmd("output HEADLESS-2 enable")
        s.wait(lambda: find(s, "e2e.tile")[1] == "21" and find(s, "e2e.h22")[1] == "22", "restored after return", 6)
        if where(s, "e2e.flo") != ("21", True, (1500, 150, 300, 200)):
            raise E2EFailure(f"float restored at {where(s, 'e2e.flo')}")
        if find(s, "e2e.tile")[2] != "HEADLESS-2":
            raise E2EFailure("ws 21 not back on HEADLESS-2")
        if e.loans():
            raise E2EFailure(f"loans left {e.loans()}")


def case_poweroff_move_when_the_departing_output_had_focus():
    """DESK 2026-10-14: focus on the output that goes away. sway carries its focused workspace
    to the remaining output as the VISIBLE one; lending there put the windows on a workspace
    of the departed output, which went home with them, so nothing returned to 21/22."""
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s, {"poweroff": {"default": "move", "grace_seconds": 1.5}}).start()
        layout(s)
        focus_ws(s, "HEADLESS-2", "21")
        launch(s, "e2e.tile")
        focus_ws(s, "HEADLESS-1", "11")
        focus_ws(s, "HEADLESS-2", "23")
        launch(s, "e2e.focused")                  # ws 23 visible + focused on the output that leaves
        time.sleep(0.4)
        s.cmd("output HEADLESS-2 disable")
        s.wait(lambda: find(s, "e2e.tile")[1] == "11" and find(s, "e2e.h22")[1] == "11",
               "lent to HEADLESS-1's own ws 11, not to the carried ws 23", 6)
        s.cmd("output HEADLESS-2 enable")
        s.wait(lambda: find(s, "e2e.tile")[1] == "21" and find(s, "e2e.h22")[1] == "22", "restored after return", 6)
        if find(s, "e2e.tile")[2] != "HEADLESS-2" or find(s, "e2e.focused")[1] != "23":
            raise E2EFailure(f"not home: tile {find(s, 'e2e.tile')[1:]}, focused {find(s, 'e2e.focused')[1:]}")
        if e.loans():
            raise E2EFailure(f"loans left {e.loans()}")


def case_poweroff_ignore_moves_nothing_extra():
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s, {"poweroff": {"default": "move", "monitors": {"second": "ignore"}, "grace_seconds": 1.0}}).start()
        layout(s)
        focus_ws(s, "HEADLESS-2", "21")
        launch(s, "e2e.tile")
        focus_ws(s, "HEADLESS-1", "11")
        time.sleep(0.4)
        s.cmd("output HEADLESS-2 disable")
        stays(s, lambda: find(s, "e2e.tile")[1] == "21" and find(s, "e2e.h22")[1] == "22", "ignore policy moved a window", 2.5)
        if "policy ignore" not in e.log:
            raise E2EFailure("grace did not run")
        s.cmd("output HEADLESS-2 enable")
        s.wait(lambda: find(s, "e2e.tile")[2] == "HEADLESS-2", "ws 21 home again (sway + reconcile)", 6)
        if e.loans():
            raise E2EFailure(f"loans {e.loans()}")


def case_every_output_off_does_nothing():
    with Nested(outputs=OUTS, config=BINDINGS) as s:
        e = Env(s, {"poweroff": {"default": "move", "grace_seconds": 1.0}}).start()
        layout(s)
        focus_ws(s, "HEADLESS-2", "21")
        launch(s, "e2e.tile")
        focus_ws(s, "HEADLESS-1", "11")
        launch(s, "e2e.own")
        time.sleep(0.4)
        s.cmd("output * disable")
        s.wait(lambda: "every output is gone" in e.log, "grace with no output", 5)
        s.cmd("output * enable")
        s.wait(lambda: find(s, "e2e.tile") and find(s, "e2e.tile")[2] == "HEADLESS-2", "ws 21 home again", 6)
        time.sleep(2.5)  # past settle: nothing may move afterwards either
        if (find(s, "e2e.tile")[1], find(s, "e2e.own")[1], find(s, "e2e.h22")[1]) != ("21", "11", "22"):
            raise E2EFailure(f"moved: {[find(s, a)[1] for a in ('e2e.tile', 'e2e.own', 'e2e.h22')]}")
        if e.loans():
            raise E2EFailure(f"loans {e.loans()}")
