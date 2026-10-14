"""Hyper+Tab overview (SWAY-15): the resident GTK4 layer-shell process against a nested
headless sway, driven by the virtual keyboard/pointer. Assertions read the process's
own state dump over its control socket (what it shows, per output) plus the sway tree.

Needs E2E_LAYER_SHELL (libgtk4-layer-shell.so, preloaded into the overview process
only) and Gtk4LayerShell-1.0 on GI_TYPELIB_PATH; sway-apps-e2e sets both.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import time
from pathlib import Path

from harness import GRIM, HERE, PYTHON, ROOT, E2EFailure, Nested

LAYER_SHELL = os.environ.get("E2E_LAYER_SHELL", "")
# A built `sway-apps-overview` wrapper instead of the checkout (tests the Nix LD_PRELOAD/typelib wiring).
OVERVIEW_BIN = os.environ.get("E2E_OVERVIEW_BIN", "")
ALT, CTRL, LOGO, SHIFT = 8, 4, 64, 1
HYPER = ALT | CTRL | LOGO
BIND = ("bindsym Mod4+Control+Mod1+Tab nop sway-apps overview\n"
        "workspace 1 output HEADLESS-1\nworkspace 2 output HEADLESS-1\nworkspace 3 output HEADLESS-1\n"
        "workspace 11 output HEADLESS-2")
OUTS = [(1280, 720), (1024, 600)]
REPORT = Path(os.environ.get("E2E_TMP") or "/tmp") / "overview-metrics.json"


class Keys:
    def __init__(self, s: Nested) -> None:
        self.p = subprocess.Popen([PYTHON, str(HERE / "vkeyboard.py")], env=s.env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True)
        s.children.append(self.p)
        if self.p.stdout.readline().strip() != "ready":
            raise E2EFailure("virtual keyboard did not start")

    def _send(self, line: str) -> None:
        self.p.stdin.write(line + "\n")
        self.p.stdin.flush()
        if self.p.stdout.readline().strip() != "ok":
            raise E2EFailure(f"virtual keyboard: {line} failed")

    def mods(self, mask: int) -> None:
        self._send(f"mods {mask}")

    def key(self, name: str) -> None:
        self._send(f"key {name}")

    def hyper_tab(self) -> float:
        self.mods(HYPER)
        t0 = time.monotonic()
        self.key("Tab")
        self.mods(0)
        return t0


class Overview:
    def __init__(self, s: Nested) -> None:
        if not OVERVIEW_BIN and (not LAYER_SHELL or not os.path.exists(LAYER_SHELL)):
            raise E2EFailure("E2E_LAYER_SHELL (libgtk4-layer-shell.so) not set")
        self.s = s
        base = s.dir / "ov"
        for d in ("state", "local", "xdg", "cache"):
            (base / d).mkdir(parents=True, exist_ok=True)
        (base / "state" / "common.json").write_text('{"version": 1}')
        (base / "state" / "E2E.json").write_text('{"version": 1}')
        self.base = base
        self.sock = str(Path(s.env["XDG_RUNTIME_DIR"]) / "sway-apps-overview.sock")
        self.env = {
            "SWAY_APPS_STATE_DIR": str(base / "state"), "SWAY_APPS_LOCAL_STATE_DIR": str(base / "local"),
            "XDG_CONFIG_HOME": str(base / "xdg"), "XDG_CACHE_HOME": str(base / "cache"),
            "SWAY_APPS_PROFILE": "E2E", "SWAY_APPS_GIT": "0", "SWAY_APPS_E2E": "1", "SWAY_APPS_GRIM_BIN": GRIM,
            "PYTHONPATH": os.pathsep.join(p for p in (str(ROOT), os.environ.get("PYTHONPATH", "")) if p),
            "GSK_RENDERER": "cairo", "GDK_DEBUG": "no-portals", "GTK_A11Y": "none",
        }
        t = time.monotonic()
        argv, env = [PYTHON, "-m", "sway_apps", "overview", "run"], {**self.env, "LD_PRELOAD": LAYER_SHELL}
        if OVERVIEW_BIN:
            argv, env = [OVERVIEW_BIN], {k: v for k, v in self.env.items() if k != "PYTHONPATH"}
            env.update({"PYTHONPATH": "", "GI_TYPELIB_PATH": ""})
        self.proc = s.spawn(argv, cwd=str(ROOT), env=env,
                            stdout=open(s.dir / "overview.out", "w"), stderr=subprocess.STDOUT)
        try:
            s.wait(lambda: self.proc.poll() is None and os.path.exists(self.sock) and self.state().get("ok"),
                   "overview process ready", 15)
        except E2EFailure as exc:
            raise E2EFailure(f"{exc}{self._tail()}")
        self.startup_ms = round(1000 * (time.monotonic() - t))

    def _tail(self) -> str:
        try:
            return " | " + (self.s.dir / "overview.out").read_text()[-600:]
        except OSError:
            return ""

    def ctl(self, line: str) -> dict:
        if self.proc.poll() is not None:
            raise E2EFailure(f"overview process exited {self.proc.returncode}{self._tail()}")
        c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        c.settimeout(5)
        c.connect(self.sock)
        c.sendall((line + "\n").encode())
        c.shutdown(socket.SHUT_WR)
        buf = b""
        while chunk := c.recv(65536):
            buf += chunk
        c.close()
        return json.loads(buf)

    def state(self) -> dict:
        return self.ctl("state")

    def cli(self, *args: str) -> dict:
        r = subprocess.run([PYTHON, "-m", "sway_apps", "--json", "overview", *args], cwd=str(ROOT), capture_output=True,
                           text=True, timeout=30, env={**self.s.env, **self.env})
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            raise E2EFailure(f"overview CLI {args}: {r.stdout[-300:]} {r.stderr[-300:]}")

    def wait_open(self) -> dict:
        try:
            return self.s.wait(lambda: (lambda st: st if st["open"] and st["painted"] else None)(self.state()),
                               "overview open and painted", 10)
        except E2EFailure as exc:
            raise E2EFailure(f"{exc}{self._tail()}")

    def wait_closed(self) -> None:
        self.s.wait(lambda: not self.state()["open"], "overview closed")


def layout(s: Nested) -> dict:
    """ws 1 (a, b) + ws 2 (c, hidden) on HEADLESS-1, ws 11 (d) on HEADLESS-2; focus a."""
    s.cmd("focus output HEADLESS-1")
    a = s.client("e2e.a", workspace="1")
    b = s.client("e2e.b")
    c = s.client("e2e.c", workspace="2")
    s.cmd("focus output HEADLESS-2")
    d = s.client("e2e.d", workspace="11")
    s.cmd("focus output HEADLESS-1")
    s.cmd("workspace 1")
    a.cmd("focus")
    s.wait(lambda: s.focused() and s.focused().get("app_id") == "e2e.a", "e2e.a focused")
    return {"a": a, "b": b, "c": c, "d": d}


def shown(st: dict) -> dict[str, list[tuple[str, bool, list[str]]]]:
    return {out: [(g["workspace"], g["visible"], [c["app_id"] for c in g["cards"]]) for g in o["groups"]]
            for out, o in st["outputs"].items()}


def record(key: str, value) -> None:
    try:
        data = json.loads(REPORT.read_text())
    except (OSError, ValueError):
        data = {}
    data.setdefault(key, []).append(value)
    REPORT.write_text(json.dumps(data))


# ---------------------------------------------------------------------------------------------
def case_hyper_tab_opens_per_output_and_esc_closes():
    with Nested(outputs=OUTS, config=BIND) as s:
        w = layout(s)
        o = Overview(s)
        keys = Keys(s)
        lat = []
        for _ in range(4):
            t0 = keys.hyper_tab()
            st = o.wait_open()
            lat.append(round(1000 * (st["painted_at"] - t0), 1))
            want = {"HEADLESS-1": [("1", True, ["e2e.a", "e2e.b"]), ("2", False, ["e2e.c"])],
                    "HEADLESS-2": [("11", True, ["e2e.d"])]}
            if shown(st) != want:
                raise E2EFailure(f"cards per output {shown(st)} != {want}")
            if st["selected"] != w["a"].con_id:
                raise E2EFailure(f"selection starts at {st['selected']}, focused is {w['a'].con_id}")
            if sorted(st["panels"]) != ["HEADLESS-1", "HEADLESS-2"]:
                raise E2EFailure(f"panels {st['panels']}")
            keys.key("Escape")
            o.wait_closed()
        record("open_latency_ms", lat)
        record("open_breakdown_ms", st["latency_ms"])
        record("rss_kb", o.state()["rss_kb"])
        record("startup_ms", o.startup_ms)
        # Hyper+Tab again closes (sway consumes the binding even while the panel holds the keyboard).
        keys.hyper_tab()
        o.wait_open()
        keys.hyper_tab()
        o.wait_closed()
        s.wait(lambda: (s.focused() or {}).get("app_id") == "e2e.a", "focus back on e2e.a after closing")


def case_keyboard_enter_focuses_window_on_hidden_workspace():
    with Nested(outputs=OUTS, config=BIND) as s:
        w = layout(s)
        o = Overview(s)
        keys = Keys(s)
        keys.hyper_tab()
        o.wait_open()
        # columns: HEADLESS-1 = ws 1 [a, b] | ws 2 [c]; HEADLESS-2 = ws 11 [d]
        for key, want in (("Down", "b"), ("Up", "a"), ("Right", "c"), ("Right", "d"), ("Left", "c"),
                          ("Tab", "d"), ("Tab", "a"), ("Tab", "b"), ("Right", "c")):
            keys.key(key)
            s.wait(lambda: o.state()["selected"] == w[want].con_id, f"{key} selects e2e.{want}")
        keys.key("Return")
        o.wait_closed()
        s.wait(lambda: s.focused() and s.focused().get("app_id") == "e2e.c", "Enter focused e2e.c")
        ws = next(x for x in s.workspaces() if x["focused"])
        if ws["name"] != "2":
            raise E2EFailure(f"workspace {ws['name']} focused, expected 2")


def case_click_focuses_window_on_other_output():
    with Nested(outputs=OUTS, config=BIND) as s:
        w = layout(s)
        o = Overview(s)
        o.cli("show")
        st = o.wait_open()
        out, x, y, cw, ch = st["bounds"][str(w["d"].con_id)]
        if out != "HEADLESS-2":
            raise E2EFailure(f"e2e.d card on {out}")
        s.click(OUTS[0][0] + x + cw // 2, y + ch // 2)
        o.wait_closed()
        s.wait(lambda: s.focused() and s.focused().get("app_id") == "e2e.d", "click focused e2e.d on HEADLESS-2")
        # A click outside every card only closes.
        o.cli("show")
        o.wait_open()
        s.click(5, 700)
        o.wait_closed()
        if s.focused().get("app_id") != "e2e.d":
            raise E2EFailure("a click on the background changed the focus")


def case_thumbnails_captured_on_focus_removed_on_close():
    with Nested(outputs=OUTS, config=BIND) as s:
        w = layout(s)
        o = Overview(s)
        thumbs = lambda: set(o.state()["thumbs"])  # noqa: E731
        a, b, c = w["a"].con_id, w["b"].con_id, w["c"].con_id
        w["b"].cmd("focus")
        s.wait(lambda: b in thumbs(), "e2e.b captured ~1 s after focus", 5)
        w["a"].cmd("focus")
        time.sleep(0.3)
        w["b"].cmd("focus")           # a loses focus before its 1 s debounce: no capture
        time.sleep(1.4)
        if a in thumbs():
            raise E2EFailure("e2e.a captured though it lost focus within the debounce")
        w["c"].cmd("focus")           # ws 2 becomes visible
        s.wait(lambda: c in thumbs(), "e2e.c captured", 5)
        w["a"].cmd("focus")
        o.cli("show")
        st = o.wait_open()
        src = {cd["app_id"]: cd["thumb"] for g in st["outputs"]["HEADLESS-1"]["groups"] for cd in g["cards"]}
        if src != {"e2e.a": "live", "e2e.b": "live", "e2e.c": "cache"}:
            raise E2EFailure(f"thumbnail sources {src}")
        o.cli("hide")
        o.wait_closed()
        s.wait(lambda: a in thumbs(), "live capture saved e2e.a to the cache")
        path = Path(st["thumb_dir"]) / f"{c}.jpg"
        if not path.exists() or path.read_bytes()[:2] != b"\xff\xd8":
            raise E2EFailure(f"{path} is not a JPEG")
        w["c"].close()
        s.wait(lambda: c not in thumbs() and not path.exists(), "thumbnail removed when e2e.c closed")


def case_fullscreen_guard():
    with Nested(outputs=OUTS, config=BIND) as s:
        layout(s)
        o = Overview(s)
        keys = Keys(s)
        s.client("e2e.game", fullscreen=True, workspace="3")
        s.wait(lambda: s.focused().get("app_id") == "e2e.game" and s.focused().get("fullscreen_mode") == 1,
               "fullscreen client focused")
        gid = s.focused()["id"]
        keys.hyper_tab()
        time.sleep(0.5)
        if o.state()["open"]:
            raise E2EFailure("opened over a focused fullscreen window")
        res = o.cli("show")
        if res.get("open") or res.get("reason") != "fullscreen":
            raise E2EFailure(f"CLI show without --force: {res}")
        o.cli("show", "--force")
        o.wait_open()
        keys.key("Escape")
        o.wait_closed()
        time.sleep(1.4)
        if gid in o.state()["thumbs"]:
            raise E2EFailure("a focused fullscreen window was captured")
