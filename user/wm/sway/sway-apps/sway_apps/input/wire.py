"""Minimal Wayland wire client (no bindings): enough for the virtual pointer and the
virtual keyboard. Requests are fire-and-forget; sync() is a wl_display.sync roundtrip,
i.e. the compositor has processed every earlier request."""
from __future__ import annotations

import os
import socket
import struct


def s_arg(text: str) -> bytes:
    raw = text.encode() + b"\0"
    return struct.pack("=I", len(raw)) + raw + b"\0" * (-len(raw) % 4)


def fixed(v: float) -> bytes:
    return struct.pack("=i", int(round(v * 256)))


class Wire:
    def __init__(self, display: str | None = None, runtime: str | None = None) -> None:
        name = display or os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
        path = name if name.startswith("/") else os.path.join(runtime or os.environ["XDG_RUNTIME_DIR"], name)
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.next_id = 2  # 1 = wl_display
        self.buf = b""
        self.globals: dict[str, tuple[int, int]] = {}
        self.registry = self.new_id()
        self.send(1, 1, struct.pack("=I", self.registry))   # wl_display.get_registry
        self.sync(self._on_global)

    def close(self) -> None:
        self.s.close()

    def new_id(self) -> int:
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj: int, opcode: int, payload: bytes = b"") -> None:
        self.s.sendall(struct.pack("=II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    def send_fd(self, obj: int, opcode: int, payload: bytes, fd: int) -> None:
        msg = struct.pack("=II", obj, ((8 + len(payload)) << 16) | opcode) + payload
        self.s.sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, struct.pack("=i", fd))])

    def read_event(self) -> tuple[int, int, bytes]:
        while len(self.buf) < 8:
            chunk = self.s.recv(65536)
            if not chunk:
                raise ConnectionError("wayland display closed")
            self.buf += chunk
        obj, word = struct.unpack("=II", self.buf[:8])
        size = word >> 16
        while len(self.buf) < size:
            self.buf += self.s.recv(65536)
        ev, self.buf = self.buf[:size], self.buf[size:]
        return obj, word & 0xFFFF, ev[8:]

    def _on_global(self, obj: int, op: int, data: bytes) -> None:
        if obj == self.registry and op == 0:                  # wl_registry.global
            name, ln = struct.unpack("=II", data[:8])
            iface = data[8:8 + ln - 1].decode()
            off = 8 + ln + (-ln % 4)
            self.globals.setdefault(iface, (name, struct.unpack("=I", data[off:off + 4])[0]))

    def sync(self, on_event=None) -> None:
        cb = self.new_id()
        self.send(1, 0, struct.pack("=I", cb))                  # wl_display.sync
        while True:
            obj, op, data = self.read_event()
            if obj == cb and op == 0:                            # wl_callback.done
                return
            if obj == 1 and op == 0:                             # wl_display.error
                raise RuntimeError(f"wayland protocol error on object {struct.unpack('=I', data[:4])[0]}")
            if on_event:
                on_event(obj, op, data)

    def bind(self, iface: str, version: int = 1) -> int:
        if iface not in self.globals:
            raise RuntimeError(f"compositor lacks {iface}")
        name, _ = self.globals[iface]
        oid = self.new_id()
        self.send(self.registry, 0, struct.pack("=I", name) + s_arg(iface) + struct.pack("=II", version, oid))
        return oid
