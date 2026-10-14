"""Native sway IPC over the unix socket (i3-ipc framing).

The CLI keeps `swayipc` (one swaymsg per call, fine for one-shot commands).
The watch daemon talks through this instead: one persistent command socket and
one event socket, no process spawn per query.
"""
from __future__ import annotations

import json
import os
import socket
import struct
from typing import Any

MAGIC = b"i3-ipc"
_HDR = struct.Struct("=6sII")

RUN_COMMAND = 0
GET_WORKSPACES = 1
SUBSCRIBE = 2
GET_OUTPUTS = 3
GET_TREE = 4
GET_BAR_CONFIG = 6
GET_SEATS = 101
EVENT_BIT = 0x80000000

# Event type numbers (high bit stripped) -> subscribe names.
EVENT_NAMES = {0: "workspace", 1: "output", 2: "mode", 3: "window", 4: "barconfig_update",
               5: "binding", 6: "shutdown", 7: "tick", 0x14: "bar_state_update", 0x15: "input"}


class IpcError(RuntimeError):
    pass


class ClosedError(IpcError):
    pass


def socket_path() -> str | None:
    """SWAYSOCK if it exists, else the session compositor's socket.

    sorted()[-1] over sway-ipc.*.sock picks by NAME: a nested test sway or the
    AION 2 meter's nested sway (a2m-v1-run) outranks the session whenever its
    pid sorts higher. The session sway is the OLDEST live one: nested ones are
    started from inside it."""
    sock = os.environ.get("SWAYSOCK")
    if sock and os.path.exists(sock):
        return sock
    uid = os.getuid()
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{uid}")
    best: tuple[float, str] | None = None
    try:
        names = os.listdir(runtime)
    except OSError:
        return None
    prefix = f"sway-ipc.{uid}."
    for name in names:
        if not (name.startswith(prefix) and name.endswith(".sock")):
            continue
        pid = name[len(prefix):-5]
        try:
            with open(f"/proc/{pid}/stat") as fh:
                stat = fh.read()
        except (OSError, ValueError):
            continue  # stale socket of a dead compositor
        # comm is in parentheses and may hold spaces; fields after it are fixed.
        rp = stat.rfind(")")
        if "sway" not in stat[stat.find("(") + 1:rp]:
            continue  # pid reused by something else
        started = int(stat[rp + 2:].split()[19])
        if best is None or started < best[0]:
            best = (started, f"{runtime}/{name}")
    return best[1] if best else None


class Connection:
    def __init__(self, path: str | None = None) -> None:
        self.path = path or socket_path()
        if not self.path:
            raise IpcError("no sway IPC socket")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(self.path)

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def fileno(self) -> int:
        return self.sock.fileno()

    def _recv_exact(self, n: int) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ClosedError("sway closed the IPC socket")
            buf += chunk
        return bytes(buf)

    def send(self, msg_type: int, payload: str = "") -> None:
        data = payload.encode()
        self.sock.sendall(_HDR.pack(MAGIC, len(data), msg_type) + data)

    def recv(self) -> tuple[int, Any]:
        magic, length, msg_type = _HDR.unpack(self._recv_exact(_HDR.size))
        if magic != MAGIC:
            raise IpcError("bad IPC magic")
        return msg_type, json.loads(self._recv_exact(length)) if length else None

    def request(self, msg_type: int, payload: str = "") -> Any:
        self.send(msg_type, payload)
        while True:
            t, body = self.recv()
            if not t & EVENT_BIT:
                return body

    def command(self, cmd: str) -> list[dict[str, Any]]:
        res = self.request(RUN_COMMAND, cmd)
        for r in res or []:
            if not r.get("success", False):
                raise IpcError(f"{cmd!r}: {r.get('error', 'unknown error')}")
        return res

    def tree(self) -> dict[str, Any]:
        return self.request(GET_TREE)

    def outputs(self) -> list[dict[str, Any]]:
        return self.request(GET_OUTPUTS)

    def workspaces(self) -> list[dict[str, Any]]:
        return self.request(GET_WORKSPACES)

    def subscribe(self, events: list[str]) -> None:
        res = self.request(SUBSCRIBE, json.dumps(events))
        if not (res or {}).get("success"):
            raise IpcError(f"subscribe {events} refused")

    def next_event(self) -> tuple[str, Any]:
        """Blocking read of one event on a subscribed connection."""
        t, body = self.recv()
        return EVENT_NAMES.get(t & ~EVENT_BIT, str(t & ~EVENT_BIT)), body
