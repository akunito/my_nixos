"""Thin wrapper around swaymsg. No third-party IPC library on purpose."""
from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import tempfile
from dataclasses import dataclass, field
from typing import Any, Iterator

from . import log, paths

_log = log.get("sway")


class SwayError(RuntimeError):
    pass


def _ensure_socket() -> None:
    """Over ssh SWAYSOCK is unset; find the live session socket."""
    if os.environ.get("SWAYSOCK") and os.path.exists(os.environ["SWAYSOCK"]):
        return
    uid = os.getuid()
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    candidates = sorted(glob.glob(f"{runtime}/sway-ipc.{uid}.*.sock"))
    if candidates:
        os.environ["SWAYSOCK"] = candidates[-1]
        _log.debug("SWAYSOCK discovered: %s", candidates[-1])


def available() -> bool:
    _ensure_socket()
    sock = os.environ.get("SWAYSOCK")
    return bool(sock and os.path.exists(sock))


def _run(args: list[str], check: bool = True) -> subprocess.CompletedProcess:
    _ensure_socket()
    cmd = [paths.SWAYMSG_BIN, *args]
    _log.debug("exec %s", " ".join(cmd))
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise SwayError(proc.stderr.strip() or proc.stdout.strip() or f"swaymsg exit {proc.returncode}")
    return proc


def get(msg_type: str) -> Any:
    return json.loads(_run(["-t", msg_type]).stdout)


def version() -> dict[str, Any]:
    return get("get_version")


def is_swayfx() -> bool:
    try:
        return "swayfx" in version().get("variant", "").lower() or "fx" in version().get("human_readable", "").lower()
    except Exception:
        return False


def command(cmd: str) -> list[dict[str, Any]]:
    """Run one sway command line, raise on the first failed sub-command."""
    proc = _run(["--", cmd], check=False)
    try:
        results = json.loads(proc.stdout) if proc.stdout.strip() else []
    except json.JSONDecodeError:
        results = []
    for r in results:
        if not r.get("success", False):
            raise SwayError(f"{cmd!r}: {r.get('error', 'unknown error')}")
    if proc.returncode != 0 and not results:
        raise SwayError(proc.stderr.strip() or f"swaymsg exit {proc.returncode}")
    _log.debug("command ok: %s", cmd)
    return results


def reload() -> None:
    command("reload")


def exec_(cmdline: str) -> None:
    """Launch through sway so the child outlives us with the session env."""
    command(f"exec {cmdline}")


def validate_config_text(text: str) -> tuple[bool, str]:
    """`sway --validate` on a temporary config holding only `text`.

    Runs against the compositor binary, without a display: config parsing
    only. Returns (ok, stderr)."""
    with tempfile.NamedTemporaryFile("w", suffix=".conf", prefix="sway-apps-validate-", delete=False) as fh:
        fh.write(text)
        path = fh.name
    try:
        proc = subprocess.run(
            [paths.SWAY_BIN, "--validate", "-c", path], capture_output=True, text=True,
            env={**os.environ, "WLR_BACKENDS": "headless"},
        )
    except FileNotFoundError:
        return True, f"{paths.SWAY_BIN} not found; validation skipped"
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    out = (proc.stderr + proc.stdout).strip()
    ok = proc.returncode == 0
    # Some sway builds print a benign "Unable to open /etc/sway/config.d" or
    # similar informational lines; the return code is what counts.
    return ok, out


# --------------------------------------------------------------------------
# Window tree

@dataclass
class Window:
    id: int
    app_id: str | None
    title: str | None
    cls: str | None
    instance: str | None
    window_role: str | None
    window_type: str | None
    shell: str | None
    pid: int | None
    workspace: str | None
    workspace_num: int | None
    output: str | None
    floating: bool
    focused: bool
    visible: bool
    sticky: bool
    fullscreen: bool
    marks: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id, "app_id": self.app_id, "title": self.title, "class": self.cls,
            "instance": self.instance, "window_role": self.window_role,
            "window_type": self.window_type, "shell": self.shell, "pid": self.pid,
            "workspace": self.workspace, "workspace_num": self.workspace_num,
            "output": self.output, "floating": self.floating, "focused": self.focused,
            "visible": self.visible, "sticky": self.sticky, "fullscreen": self.fullscreen,
            "marks": self.marks,
        }

    @property
    def label(self) -> str:
        return self.app_id or self.cls or self.title or f"con {self.id}"


def _walk(node: dict[str, Any], output: str | None, ws: dict[str, Any] | None) -> Iterator[Window]:
    ntype = node.get("type")
    if ntype == "output":
        output = node.get("name")
    if ntype == "workspace":
        ws = node
    if ntype in ("con", "floating_con") and (node.get("app_id") or node.get("window_properties") or node.get("pid")):
        props = node.get("window_properties") or {}
        yield Window(
            id=node["id"],
            app_id=node.get("app_id"),
            title=node.get("name"),
            cls=props.get("class"),
            instance=props.get("instance"),
            window_role=props.get("window_role"),
            window_type=props.get("window_type"),
            shell=node.get("shell"),
            pid=node.get("pid"),
            workspace=ws.get("name") if ws else None,
            workspace_num=ws.get("num") if ws else None,
            output=output,
            floating=ntype == "floating_con",
            focused=bool(node.get("focused")),
            visible=bool(node.get("visible")),
            sticky=bool(node.get("sticky")),
            fullscreen=bool(node.get("fullscreen_mode")),
            marks=list(node.get("marks") or []),
        )
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        yield from _walk(child, output, ws)


def windows() -> list[Window]:
    tree = get("get_tree")
    return [w for w in _walk(tree, None, None) if w.output != "__i3"]


def focused_window() -> Window | None:
    for w in windows():
        if w.focused:
            return w
    return None


def workspaces() -> list[dict[str, Any]]:
    return get("get_workspaces")


def outputs() -> list[dict[str, Any]]:
    return get("get_outputs")


def wait_for_focus_change(timeout: float) -> Window | None:
    """Block until the user focuses a window (the CLI "pick" mode)."""
    _ensure_socket()
    try:
        proc = subprocess.run(
            [paths.SWAYMSG_BIN, "-t", "subscribe", '["window"]'],
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None
    try:
        event = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    if event.get("change") not in ("focus", "new"):
        return focused_window()
    cid = event.get("container", {}).get("id")
    for w in windows():
        if w.id == cid:
            return w
    return focused_window()


_RE_CACHE: dict[str, re.Pattern] = {}


def _match(pattern: str, value: str | None) -> bool:
    """sway criteria: POSIX extended regex, unanchored, case-sensitive."""
    if value is None:
        return False
    if pattern == "__focused__":
        return True  # handled by the caller
    rx = _RE_CACHE.get(pattern)
    if rx is None:
        try:
            rx = re.compile(pattern)
        except re.error:
            rx = re.compile(re.escape(pattern))
        _RE_CACHE[pattern] = rx
    return rx.search(value) is not None


def window_matches(w: Window, criteria: dict[str, str]) -> bool:
    for key, pat in criteria.items():
        if key == "app_id":
            if not _match(pat, w.app_id):
                return False
        elif key == "class":
            if not _match(pat, w.cls):
                return False
        elif key == "instance":
            if not _match(pat, w.instance):
                return False
        elif key == "title":
            if not _match(pat, w.title):
                return False
        elif key == "window_role":
            if not _match(pat, w.window_role):
                return False
        elif key == "window_type":
            if not _match(pat, w.window_type):
                return False
        elif key == "shell":
            if not _match(pat, w.shell):
                return False
        elif key == "workspace":
            if not _match(pat, w.workspace):
                return False
        elif key == "con_mark":
            if not any(_match(pat, m) for m in w.marks):
                return False
        elif key == "con_id":
            if str(w.id) != pat:
                return False
        elif key == "pid":
            if str(w.pid) != pat:
                return False
        elif key == "floating":
            if not w.floating:
                return False
        elif key == "tiling":
            if w.floating:
                return False
        elif key == "urgent":
            pass
        else:
            # Unknown criterion: be conservative, don't match.
            return False
    return True
