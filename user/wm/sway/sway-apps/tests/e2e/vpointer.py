"""Persistent virtual pointer (zwlr_virtual_pointer_v1) in pure Python, no bindings.

Why not wlrctl: it creates a device per invocation and destroys it on exit, and
with WLR_LIBINPUT_NO_DEVICES the seat then has no pointer capability most of the
time, so GTK never creates a wl_pointer and clicks are lost. It also has no
press/hold/release. This one lives for the whole Nested session.

Reads commands on stdin, one per line, answers "ok" after a display sync:
  abs X Y W H      absolute motion inside a W x H layout extent
  press BTN | release BTN    (272 left, 273 right, 274 middle)
  scroll DY        vertical axis, in steps of 15 (one wheel notch)
"""
from __future__ import annotations

import os
import socket
import struct
import sys
import time

BTN = {"left": 272, "right": 273, "middle": 274}


class Wire:
    def __init__(self) -> None:
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ["WAYLAND_DISPLAY"])
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.next_id = 2  # 1 = wl_display
        self.buf = b""

    def new_id(self) -> int:
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj: int, opcode: int, payload: bytes = b"") -> None:
        self.s.sendall(struct.pack("=II", obj, ((8 + len(payload)) << 16) | opcode) + payload)

    def read_event(self) -> tuple[int, int, bytes]:
        while len(self.buf) < 8:
            self.buf += self.s.recv(4096)
        obj, word = struct.unpack("=II", self.buf[:8])
        size = word >> 16
        while len(self.buf) < size:
            self.buf += self.s.recv(4096)
        ev, self.buf = self.buf[:size], self.buf[size:]
        return obj, word & 0xFFFF, ev[8:]

    def sync(self) -> None:
        cb = self.new_id()
        self.send(1, 0, struct.pack("=I", cb))       # wl_display.sync
        while True:
            obj, op, _ = self.read_event()
            if obj == cb and op == 0:                 # wl_callback.done
                return
            if obj == 1 and op == 0:                  # wl_display.error
                raise RuntimeError("wayland protocol error")


def s_arg(text: str) -> bytes:
    raw = text.encode() + b"\0"
    return struct.pack("=I", len(raw)) + raw + b"\0" * (-len(raw) % 4)


def fixed(v: float) -> bytes:
    return struct.pack("=i", int(round(v * 256)))


def main() -> int:
    w = Wire()
    reg = w.new_id()
    w.send(1, 1, struct.pack("=I", reg))              # wl_display.get_registry
    cb = w.new_id()
    w.send(1, 0, struct.pack("=I", cb))
    mgr_name = None
    while True:
        obj, op, data = w.read_event()
        if obj == reg and op == 0:                     # wl_registry.global
            name, ln = struct.unpack("=II", data[:8])
            iface = data[8:8 + ln - 1].decode()
            if iface == "zwlr_virtual_pointer_manager_v1":
                mgr_name = name
        elif obj == cb and op == 0:
            break
    if mgr_name is None:
        print("no zwlr_virtual_pointer_manager_v1", flush=True)
        return 1
    mgr = w.new_id()
    w.send(reg, 0, struct.pack("=I", mgr_name) + s_arg("zwlr_virtual_pointer_manager_v1") + struct.pack("=II", 1, mgr))
    ptr = w.new_id()
    w.send(mgr, 0, struct.pack("=II", 0, ptr))        # create_virtual_pointer(seat=null, id)
    w.sync()
    print("ready", flush=True)
    for line in sys.stdin:
        parts = line.split()
        if not parts:
            continue
        t = int(time.monotonic() * 1000) & 0xFFFFFFFF
        cmd = parts[0]
        if cmd == "abs":
            x, y, ew, eh = (int(v) for v in parts[1:5])
            w.send(ptr, 1, struct.pack("=IIIII", t, x, y, ew, eh))
        elif cmd in ("press", "release"):
            b = BTN.get(parts[1]) or int(parts[1])
            w.send(ptr, 2, struct.pack("=III", t, b, 1 if cmd == "press" else 0))
        elif cmd == "scroll":
            dy = float(parts[1])
            w.send(ptr, 5, struct.pack("=I", 0))       # axis_source wheel
            w.send(ptr, 7, struct.pack("=II", t, 0) + fixed(dy * 15) + struct.pack("=i", int(dy)))  # axis_discrete
        w.send(ptr, 4)                                  # frame
        w.sync()
        print("ok", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
