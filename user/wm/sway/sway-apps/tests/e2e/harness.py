"""Nested headless sway for the e2e suite. Never touches the live session:
own XDG_RUNTIME_DIR (so sway-apps' socket discovery cannot see it), own
WAYLAND_DISPLAY/SWAYSOCK, children killed by pid (never pkill -f).

    with Nested(outputs=[(1280, 720), (1024, 600)]) as s:
        a = s.client("e2e.a", size="400x300", floating=True)
        s.click(100, 100)
        s.wait(lambda: "press 1" in a.log_text(), "click reached e2e.a")

Tools come from the environment (sway-apps-e2e sets them): E2E_SWAY,
E2E_GRIM, E2E_WAYBAR, E2E_PYTHON (a python with pygobject + gtk4 typelibs).
"""
from __future__ import annotations

import glob
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Callable, Iterator

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]                       # .../sway-apps
sys.path.insert(0, str(ROOT))

from sway_apps import ipc  # noqa: E402

SWAY = os.environ.get("E2E_SWAY", "sway")
GRIM = os.environ.get("E2E_GRIM", "grim")
WAYBAR = os.environ.get("E2E_WAYBAR", "waybar")
PYTHON = os.environ.get("E2E_PYTHON", sys.executable)
TMP = os.environ.get("E2E_TMP") or tempfile.gettempdir()
DEFAULT_TIMEOUT = float(os.environ.get("E2E_TIMEOUT", "5"))


class E2EFailure(AssertionError):
    pass


def walk(node: dict[str, Any]) -> Iterator[dict[str, Any]]:
    yield node
    for c in node.get("nodes", []) + node.get("floating_nodes", []):
        yield from walk(c)


class Client:
    def __init__(self, nested: "Nested", app_id: str, proc: subprocess.Popen, log: Path) -> None:
        self.nested, self.app_id, self.proc, self.log = nested, app_id, proc, log

    def node(self) -> dict[str, Any] | None:
        for n in walk(self.nested.tree()):
            if n.get("app_id") == self.app_id:
                return n
        return None

    @property
    def con_id(self) -> int:
        n = self.node()
        if n is None:
            raise E2EFailure(f"{self.app_id} is not in the tree")
        return n["id"]

    def cmd(self, command: str) -> list[dict[str, Any]]:
        return self.nested.cmd(f"[con_id={self.con_id}] {command}")

    def rect(self) -> dict[str, int]:
        return self.node()["rect"]

    def log_text(self) -> str:
        try:
            return self.log.read_text()
        except FileNotFoundError:
            return ""

    def clear_log(self) -> None:
        self.log.write_text("")

    def close(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()


class Nested:
    def __init__(self, outputs: list[tuple[int, int]] | int = 1, config: str = "", scales: list[float] | None = None,
                 sway: str | None = None, env: dict[str, str] | None = None) -> None:
        if isinstance(outputs, int):
            outputs = [(1280, 720)] * outputs
        self.outputs_spec = outputs
        self.scales = scales or [1.0] * len(outputs)
        self.extra = config
        self.sway_bin = sway or SWAY
        self.extra_env = env or {}
        self.dir = Path(tempfile.mkdtemp(prefix="sway-e2e-", dir=TMP))
        # Unix socket paths are capped at 108 bytes: a scratch dir is far too long
        # for "<runtime>/wayland-1" ("Unable to open wayland socket"). A subdir of
        # the real runtime dir is short, and the live session's socket discovery
        # only scans the top level of it, so it never sees this sway.
        base = os.environ.get("E2E_RUNTIME_ROOT") or os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self.runtime = Path(tempfile.mkdtemp(prefix="se2e-", dir=base))
        self.proc: subprocess.Popen | None = None
        self.children: list[subprocess.Popen] = []
        self.clients: list[Client] = []
        self._conn: ipc.Connection | None = None
        self._vptr: subprocess.Popen | None = None
        self.env: dict[str, str] = {}

    # ---- lifecycle -----------------------------------------------------------------
    def config_text(self) -> str:
        lines = ["xwayland disable", "focus_follows_mouse no", "default_border pixel 2",
                 "seat seat0 hide_cursor 0"]
        x = 0
        for i, ((w, h), sc) in enumerate(zip(self.outputs_spec, self.scales), start=1):
            lines.append(f"output HEADLESS-{i} resolution {w}x{h} position {x} 0 scale {sc}")
            x += round(w / sc)
        lines.append(self.extra)
        return "\n".join(lines) + "\n"

    def start(self) -> "Nested":
        cfg = self.dir / "sway.cfg"
        cfg.write_text(self.config_text())
        env = {k: v for k, v in os.environ.items()
               if k not in ("WAYLAND_DISPLAY", "SWAYSOCK", "DISPLAY", "LD_LIBRARY_PATH", "I3SOCK")}
        env.update({"XDG_RUNTIME_DIR": str(self.runtime), "WLR_BACKENDS": "headless",
                    "WLR_HEADLESS_OUTPUTS": str(len(self.outputs_spec)), "WLR_RENDERER": "pixman",
                    "WLR_LIBINPUT_NO_DEVICES": "1"})
        env.update(self.extra_env)
        self.proc = subprocess.Popen([self.sway_bin, "-c", str(cfg)], env=env, stdout=open(self.dir / "sway.log", "w"),
                                     stderr=subprocess.STDOUT, start_new_session=True)
        sock = self.wait(lambda: (glob.glob(str(self.runtime / "sway-ipc.*.sock")) or [None])[0], "sway IPC socket", 10)
        wl = self.wait(lambda: next((p for p in glob.glob(str(self.runtime / "wayland-*")) if not p.endswith(".lock")), None),
                       "wayland socket", 10)
        self.env = {**env, "SWAYSOCK": sock, "WAYLAND_DISPLAY": Path(wl).name, "GDK_BACKEND": "wayland"}
        for k in ("WLR_BACKENDS", "WLR_HEADLESS_OUTPUTS", "WLR_RENDERER", "WLR_LIBINPUT_NO_DEVICES"):
            self.env.pop(k, None)
        self.wait(lambda: len([o for o in self.outputs() if o.get("active")]) == len(self.outputs_spec), "outputs active", 10)
        return self

    def stop(self) -> None:
        for c in self.clients:
            c.close()
        for p in self.children:
            if p.poll() is None:
                p.terminate()
        for p in self.children:
            try:
                p.wait(3)
            except subprocess.TimeoutExpired:
                p.kill()
        if self._conn:
            self._conn.close()
        if self.proc and self.proc.poll() is None:
            os.killpg(self.proc.pid, signal.SIGTERM)
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                os.killpg(self.proc.pid, signal.SIGKILL)
        shutil.rmtree(self.runtime, ignore_errors=True)
        if os.environ.get("E2E_KEEP") != "1":
            shutil.rmtree(self.dir, ignore_errors=True)

    def __enter__(self) -> "Nested":
        return self.start()

    def __exit__(self, *exc) -> None:
        self.stop()

    # ---- IPC -------------------------------------------------------------------------
    @property
    def conn(self) -> ipc.Connection:
        if self._conn is None:
            self._conn = ipc.Connection(self.env["SWAYSOCK"])
        return self._conn

    def cmd(self, command: str) -> list[dict[str, Any]]:
        return self.conn.command(command)

    def tree(self) -> dict[str, Any]:
        return self.conn.tree()

    def outputs(self) -> list[dict[str, Any]]:
        return ipc.Connection(self.env["SWAYSOCK"]).outputs() if not self._conn else self.conn.outputs()

    def workspaces(self) -> list[dict[str, Any]]:
        return self.conn.workspaces()

    def focused(self) -> dict[str, Any] | None:
        return next((n for n in walk(self.tree()) if n.get("focused")), None)

    # ---- waiting ---------------------------------------------------------------------
    def wait(self, pred: Callable[[], Any], what: str, timeout: float | None = None) -> Any:
        end = time.monotonic() + (timeout or DEFAULT_TIMEOUT)
        last: Exception | None = None
        while time.monotonic() < end:
            try:
                v = pred()
                if v:
                    return v
            except (ipc.IpcError, OSError, KeyError, TypeError, E2EFailure) as exc:
                last = exc
            time.sleep(0.02)
        raise E2EFailure(f"timed out waiting for {what}" + (f" (last error: {last})" if last else ""))

    # ---- processes -------------------------------------------------------------------
    def spawn(self, argv: list[str], env: dict[str, str] | None = None, **kw) -> subprocess.Popen:
        p = subprocess.Popen(argv, env={**self.env, **(env or {})}, **kw)
        self.children.append(p)
        return p

    def client(self, app_id: str, size: str = "400x300", title: str | None = None, floating: bool = False,
               fullscreen: bool = False, workspace: str | None = None) -> Client:
        log = self.dir / f"{app_id}.log"
        argv = [PYTHON, str(HERE / "client.py"), "--app-id", app_id, "--size", size, "--log", str(log)]
        if title:
            argv += ["--title", title]
        if fullscreen:
            argv.append("--fullscreen")
        if floating:
            self.cmd(f'for_window [app_id="^{app_id}$"] floating enable')
        if workspace:
            self.cmd(f"workspace {workspace}")
        p = subprocess.Popen(argv, env=self.env, stdout=subprocess.DEVNULL, stderr=open(self.dir / f"{app_id}.err", "w"))
        c = Client(self, app_id, p, log)
        self.clients.append(c)
        self.wait(lambda: c.node() is not None and c.node().get("visible", True), f"{app_id} mapped", 10)
        return c

    # ---- input (persistent virtual pointer, vpointer.py) ----------------------------------
    def _vp(self, line: str) -> None:
        if self._vptr is None:
            self._vptr = subprocess.Popen([PYTHON, str(HERE / "vpointer.py")], env=self.env, stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, text=True)
            self.children.append(self._vptr)
            if self._vptr.stdout.readline().strip() != "ready":
                raise E2EFailure("virtual pointer did not start")
        self._vptr.stdin.write(line + "\n")
        self._vptr.stdin.flush()
        if self._vptr.stdout.readline().strip() != "ok":
            raise E2EFailure(f"virtual pointer: {line} failed")

    def layout_extent(self) -> tuple[int, int]:
        outs = [o["rect"] for o in self.outputs() if o.get("active")]
        return max(r["x"] + r["width"] for r in outs), max(r["y"] + r["height"] for r in outs)

    def pointer_to(self, x: int, y: int) -> None:
        w, h = self.layout_extent()
        self._vp(f"abs {x} {y} {w} {h}")

    def press(self, x: int, y: int, button: str = "left") -> None:
        self.pointer_to(x, y)
        self._vp(f"press {button}")

    def release(self, button: str = "left") -> None:
        self._vp(f"release {button}")

    def click(self, x: int, y: int, button: str = "left") -> None:
        self.press(x, y, button)
        self.release(button)

    def scroll(self, x: int, y: int, notches: int) -> None:
        """notches > 0 = wheel down (button5), < 0 = wheel up (button4)."""
        self.pointer_to(x, y)
        self._vp(f"scroll {notches}")

    # ---- capture -----------------------------------------------------------------------
    def grab(self, name: str, geometry: str | None = None) -> Path:
        out = self.dir / f"{name}.png"
        argv = [GRIM] + (["-g", geometry] if geometry else []) + [str(out)]
        subprocess.run(argv, env=self.env, check=True, capture_output=True, timeout=10)
        return out
