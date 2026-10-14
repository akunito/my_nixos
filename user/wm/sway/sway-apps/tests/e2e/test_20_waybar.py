"""Per-monitor Waybar (SWAY-2..5) with a real Waybar in the nested sway.

Two outputs, roles main=HEADLESS-1 (primary) and second=HEADLESS-2, a test
catalog (workspaces, clock, a custom module, tray) whose base CSS paints
workspace buttons solid red, so a grim crop of a bar says how many buttons it
draws. Everything sway-apps writes goes to a scratch XDG_CONFIG_HOME / state /
local dir. Waybar runs under a respawn loop and sway-apps restarts it through
SWAY_APPS_WAYBAR_PIDFILE (this Waybar, on the suite's private bus, aborts on
SIGUSR2; the session's does not), so it is never the live session's.
"""
from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

from harness import PYTHON, ROOT, WAYBAR, E2EFailure, Nested

BAR_H = 30
CATALOG = {
    "version": 1,
    "modules": {
        "sway/workspaces": {"disable-scroll": True, "format": "{name}"},
        "clock": {"format": "{:%H:%M}", "interval": 60},
        "custom/x": {"exec": "echo x", "interval": 3600},
        "tray": {"icon-spacing": 4},
    },
    "layouts": {t: {"left": ["custom/x"], "center": ["sway/workspaces"], "right": ["tray", "clock"]}
                for t in ("primary", "secondary")},
    "bar": {"layer": "top", "position": "top", "height": BAR_H, "spacing": 0},
    "sizes": {"font": 12, "tray_icon": 16},
    "default_visible": "all",
}
BASE_CSS = """* { font-family: sans-serif; font-size: 12px; min-height: 0; border: none; border-radius: 0; box-shadow: none; }
window#waybar { background: #000000; color: #ffffff; }
#workspaces button, #workspaces button.focused, #workspaces button:hover {
  background: #ff0000; background-image: none; color: #ff0000; min-width: 40px; padding: 0 4px; margin: 0 2px; }
#clock, #custom-x { padding: 0 6px; color: #ffffff; }
"""


class Bars:
    """Scratch sway-apps state + nested sway + Waybar (+ the watch daemon)."""

    def __init__(self, daemon: bool = True) -> None:
        self.daemon = daemon
        self.s: Nested | None = None
        self.waybar: subprocess.Popen | None = None

    def __enter__(self) -> "Bars":
        tmp = Path(os.environ.get("E2E_TMP") or "/tmp")
        import tempfile
        self.root = Path(tempfile.mkdtemp(prefix="wb-", dir=tmp))
        self.cfg = self.root / "cfg"
        (self.cfg / "sway-apps").mkdir(parents=True)
        (self.cfg / "sway-apps" / "waybar-modules.json").write_text(json.dumps(CATALOG))
        (self.cfg / "sway-apps" / "waybar-base.css").write_text(BASE_CSS)
        state = self.root / "state"
        state.mkdir()
        (state / "E2E.json").write_text(json.dumps({"version": 1, "monitors": [
            {"id": "main", "criteria": "HEADLESS-1", "group": 0, "primary": True},
            {"id": "second", "criteria": "HEADLESS-2", "group": 0}]}))
        self.env = {
            "SWAY_APPS_E2E": "1", "SWAY_APPS_GIT": "0", "SWAY_APPS_PROFILE": "E2E", "SWAY_APPS_DOTFILES": str(self.root),
            "SWAY_APPS_STATE_DIR": str(state), "SWAY_APPS_LOCAL_STATE_DIR": str(self.root / "local"),
            "XDG_CONFIG_HOME": str(self.cfg), "PYTHONPATH": str(ROOT), "SWAY_APPS_TMUX_RELOAD": "0",
        }
        # Files first: the nested sway's config includes the bar blocks.
        pre = {**os.environ, **self.env, "SWAYSOCK": str(self.root / "none.sock"), "XDG_RUNTIME_DIR": str(self.root)}
        pre.pop("LD_LIBRARY_PATH", None)
        r = subprocess.run([PYTHON, "-m", "sway_apps", "--json", "waybar", "apply", "--no-reload"], env=pre,
                           capture_output=True, text=True, timeout=30)
        if r.returncode:
            raise E2EFailure(f"waybar apply: {r.stderr[-500:]}")
        try:
            return self._start()
        except BaseException:
            self.__exit__()
            raise

    def _start(self) -> "Bars":
        conf = (f"include {self.cfg}/sway/sway-apps-bars.conf\n"
                "bindsym --whole-window button8 nop sway-apps waybar toggle\n")
        self.s = Nested(outputs=[(1280, 720), (1024, 600)], config=conf).start()
        self.pidfile = self.root / "waybar.pid"
        argv = [WAYBAR, "-c", str(self.cfg / "waybar" / "config"), "-s", str(self.cfg / "waybar" / "style.css")]
        if os.environ.get("E2E_WAYBAR_DEBUG") == "1":
            argv += ["-l", "debug"]
        loop = ('while [ ! -e "$STOP" ]; do "$@" >> "$LOG" 2>&1 & echo $! > "$PIDFILE"; wait $!; done')
        self.waybar = self.s.spawn(["bash", "-c", loop, "waybar-loop", *argv], start_new_session=True,
                                   env={"XDG_CONFIG_HOME": str(self.cfg), "STOP": str(self.root / "stop"),
                                        "LOG": str(self.s.dir / "waybar.log"), "PIDFILE": str(self.pidfile)})
        self.env["SWAY_APPS_WAYBAR_PIDFILE"] = str(self.pidfile)
        self.wait_bar("HEADLESS-1", BAR_H, 15)
        self.wait_bar("HEADLESS-2", BAR_H, 5)
        if self.daemon:
            self.s.spawn([PYTHON, "-m", "sway_apps", "watch"], env=self.env, stdout=open(self.s.dir / "watch.out", "w"),
                         stderr=subprocess.STDOUT)
            self.s.wait(lambda: "watching" in self.daemon_log(), "watch daemon up", 10)
        return self

    def __exit__(self, *exc) -> None:
        (self.root / "stop").touch()
        if self.waybar is not None and self.waybar.poll() is None:
            try:
                os.killpg(self.waybar.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if self.s:
            if os.environ.get("E2E_KEEP") == "1":
                print(f"  kept {self.s.dir} {self.root}", flush=True)
            self.s.stop()

    # ---- helpers -------------------------------------------------------------------
    def cli(self, *args: str) -> dict:
        r = subprocess.run([PYTHON, "-m", "sway_apps", "--json", "waybar", *args], env={**self.s.env, **self.env},
                           capture_output=True, text=True, timeout=30)
        if r.returncode:
            raise E2EFailure(f"sway-apps waybar {' '.join(args)}: {r.stdout[-300:]} {r.stderr[-500:]}")
        return json.loads(r.stdout) if r.stdout.strip() else {}

    def daemon_log(self) -> str:
        try:
            return (self.root / "local" / "sway-apps.log").read_text()
        except OSError:
            return ""

    def bar_y(self, output: str) -> int | None:
        for w in self.s.workspaces():
            if w.get("visible") and w.get("output") == output:
                return w["rect"]["y"]
        return None

    def wait_bar(self, output: str, y: int, timeout: float = 5) -> None:
        self.s.wait(lambda: self.bar_y(output) == y, f"{output} workspace at y={y} (now {self.bar_y(output)})", timeout)

    def hold_bar(self, output: str, y: int, seconds: float = 0.8) -> None:
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if self.bar_y(output) != y:
                raise E2EFailure(f"{output}: workspace moved to y={self.bar_y(output)}, expected to stay {y}")
            time.sleep(0.05)

    def red_columns(self, output: str, name: str) -> int:
        """Columns of the output's bar that hold workspace-button red."""
        o = next(o for o in self.s.outputs() if o["name"] == output)
        r = o["rect"]
        png = self.s.grab(name, f"{r['x']},{r['y']} {r['width']}x{BAR_H}")
        import gi
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf
        pb = GdkPixbuf.Pixbuf.new_from_file(str(png))
        w, h, n, stride = pb.get_width(), pb.get_height(), pb.get_n_channels(), pb.get_rowstride()
        px = pb.get_pixels()
        cols = 0
        for x in range(w):
            for y in range(0, h, 2):
                i = y * stride + x * n
                if px[i] > 200 and px[i + 1] < 60 and px[i + 2] < 60:
                    cols += 1
                    break
        return cols

    def wait_cols(self, output: str, pred, what: str, timeout: float = 6) -> int:
        last = {"v": -1}

        def check() -> bool:
            last["v"] = self.red_columns(output, f"bar-{output}")
            return pred(last["v"])
        try:
            self.s.wait(check, what, timeout)
        except E2EFailure as exc:
            wss = ", ".join(f"{w['name']}@{w['output']}{'*' if w.get('visible') else ''}" for w in self.s.workspaces())
            raise E2EFailure(f"{exc}; red columns {last['v']}; workspaces {wss}") from None
        return last["v"]


def three_workspaces(b: Bars) -> None:
    """HEADLESS-1: ws 11 (window) + ws 13 (visible); HEADLESS-2: ws 21 (visible).
    Fresh numbers: sway's initial "1"/"2" may sit on either output."""
    s = b.s
    s.cmd("focus output HEADLESS-2")
    s.cmd("workspace 21")
    s.cmd("focus output HEADLESS-1")
    s.client("e2e.a", workspace="11")
    s.client("e2e.b", workspace="13")
    s.wait(lambda: sorted((w["name"], w["output"]) for w in s.workspaces())
           == [("11", "HEADLESS-1"), ("13", "HEADLESS-1"), ("21", "HEADLESS-2")], "workspaces 11,13 | 21")


ONE_BUTTON = lambda c: 20 < c < 75      # one ~48 px button
ALL_BUTTONS = lambda c: c > 120          # three of them


def case_waybar_hide_show_per_bar_and_reload_persistence():
    with Bars(daemon=False) as b:
        b.cli("hide", "--bar", "second")
        b.wait_bar("HEADLESS-2", 0)
        b.hold_bar("HEADLESS-1", BAR_H, 0.3)
        if "mode invisible" not in (b.cfg / "sway" / "sway-apps-bars.conf").read_text().split("id wb-second", 1)[1][:80]:
            raise E2EFailure("bar block not persisted")
        b.s.cmd("reload")
        b.hold_bar("HEADLESS-2", 0, 1.0)      # reload resends the file's mode: still hidden
        b.hold_bar("HEADLESS-1", BAR_H, 0.2)
        b.cli("show", "--output", "HEADLESS-2")
        b.wait_bar("HEADLESS-2", BAR_H)
        st = b.cli("status")
        if [x["visible"] for x in st["bars"]] != [True, True, False]:
            raise E2EFailure(f"status {st['bars']}")


def case_waybar_hotkey_toggles_focused_monitor():
    with Bars() as b:
        b.s.cmd("focus output HEADLESS-2")
        lat = []
        for expect in (0, BAR_H, 0):
            b.s.pointer_to(1280 + 500, 300)
            t0 = time.perf_counter()
            b.s._vp("press 275")          # BTN_SIDE = sway button8 -> nop sway-apps waybar toggle
            b.s._vp("release 275")
            while b.bar_y("HEADLESS-2") != expect:
                if time.perf_counter() - t0 > 3:
                    raise E2EFailure(f"hotkey: HEADLESS-2 bar not at y={expect}")
                time.sleep(0.002)
            lat.append((time.perf_counter() - t0) * 1000)
            b.hold_bar("HEADLESS-1", BAR_H, 0.1)
        verb = [float(x) for x in re.findall(r"waybar toggle\s+in ([0-9.]+) ms", b.daemon_log())]
        print(f"  hotkey: press -> workspace rect moved {', '.join(f'{x:.1f}' for x in lat)} ms; "
              f"daemon verb {', '.join(f'{x:.1f}' for x in verb)} ms", flush=True)
        if json.loads((b.root / "local" / "waybar.json").read_text())["bars"]["second"]["visible"] is not False:
            raise E2EFailure("hotkey state not persisted locally")


def case_waybar_workspaces_this_monitor_vs_all():
    with Bars() as b:
        three_workspaces(b)
        b.wait_cols("HEADLESS-2", ONE_BUTTON, "HEADLESS-2 bar shows only its own workspace")
        b.cli("ws", "second", "all")
        b.wait_cols("HEADLESS-2", ALL_BUTTONS, "HEADLESS-2 bar shows all workspaces")
        b.cli("ws", "second", "output")
        b.wait_cols("HEADLESS-2", ONE_BUTTON, "back to this monitor")


def case_waybar_auto_all_when_other_bar_hidden_or_fullscreen():
    with Bars() as b:
        three_workspaces(b)
        b.wait_cols("HEADLESS-1", lambda c: 60 < c < 120, "HEADLESS-1 shows its two workspaces")
        b.cli("hide", "--bar", "second")
        b.wait_cols("HEADLESS-1", ALL_BUTTONS, "only visible bar shows all")
        b.cli("show", "--bar", "second")
        b.wait_cols("HEADLESS-1", lambda c: 60 < c < 120, "two bars again: own workspaces")
        # A fullscreen client on HEADLESS-2's visible workspace: its bar is not drawn.
        b.s.cmd("focus output HEADLESS-2")
        g = b.s.client("e2e.game", workspace="21")
        t0 = time.perf_counter()
        g.cmd("fullscreen enable")
        b.wait_cols("HEADLESS-1", ALL_BUTTONS, "fullscreen on the other output -> all")
        print(f"  fullscreen -> CSS applied and drawn within {(time.perf_counter() - t0) * 1000:.0f} ms (incl. grim polls)", flush=True)
        g.cmd("fullscreen disable")
        b.wait_cols("HEADLESS-1", lambda c: 60 < c < 120, "fullscreen gone -> own workspaces")


def case_waybar_size_live_and_ipc_after_restart():
    with Bars() as b:
        b.cli("size", "main", "150")
        # height 30 * 150 % = 45 in the config (Waybar grows it to what the
        # scaled paddings need); CSS changed -> Waybar restarted.
        b.s.wait(lambda: (b.bar_y("HEADLESS-1") or 0) >= 45, f"HEADLESS-1 bar >= 45 px (now {b.bar_y('HEADLESS-1')})", 8)
        tall = b.bar_y("HEADLESS-1")
        b.hold_bar("HEADLESS-2", BAR_H, 0.2)
        css = (b.cfg / "waybar" / "sway-apps.css").read_text()
        if "window#waybar.wb-main * { font-size: 18px; }" not in css:
            raise E2EFailure("size CSS missing")
        # Waybar reloaded: per-bar IPC control must still work.
        b.cli("hide", "--bar", "main")
        b.wait_bar("HEADLESS-1", 0)
        b.cli("show", "--bar", "main")
        b.wait_bar("HEADLESS-1", tall)
        if b.waybar.poll() is not None:
            raise E2EFailure("waybar loop died")
        b.cli("reset")
        b.wait_bar("HEADLESS-1", BAR_H, 8)


def case_waybar_refresh_and_css_cost():
    """Measured in-process over the nested sway: one effective-visibility pass
    (get_tree + modes + one IPC message when a mode changes) and a CSS render+write."""
    with Bars(daemon=False) as b:
        three_workspaces(b)
        code = r"""
import json, time
from sway_apps import waybar
rt = waybar.Runtime(); sw = waybar.SwayLink.connect()
rt.refresh(sw)
med = lambda x: sorted(x)[len(x) // 2]
flip, same, css, tree = [], [], [], []
for i in range(40):
    rt.model().by_key["second"].ws = "all" if i % 2 else "output"
    t0 = time.perf_counter(); rt.refresh(sw); flip.append((time.perf_counter() - t0) * 1000)
for i in range(40):
    t0 = time.perf_counter(); rt.refresh(sw); same.append((time.perf_counter() - t0) * 1000)
for i in range(40):
    rt.model().by_key["main"].size = 100 + (i % 2) * 20
    t0 = time.perf_counter(); waybar.write_if_changed(waybar.CSS_FILE, waybar.render_css(rt.model())); css.append((time.perf_counter() - t0) * 1000)
for i in range(40):
    t0 = time.perf_counter(); sw.tree(); tree.append((time.perf_counter() - t0) * 1000)
print(json.dumps({"flip": med(flip), "same": med(same), "css": med(css), "tree": med(tree)}))
"""
        r = subprocess.run([PYTHON, "-c", code], env={**b.s.env, **b.env}, capture_output=True, text=True, timeout=60)
        if r.returncode:
            raise E2EFailure(r.stderr[-500:])
        d = json.loads(r.stdout.strip().splitlines()[-1])
        print(f"  refresh with a mode change {d['flip']:.2f} ms, without {d['same']:.2f} ms (get_tree {d['tree']:.2f} ms); "
              f"CSS render+write {d['css']:.2f} ms; medians of 40", flush=True)
