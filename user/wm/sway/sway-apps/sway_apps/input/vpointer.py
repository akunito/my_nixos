"""Persistent zwlr_virtual_pointer_v1 - the live and nested pointer backend.

Not `seat seat0 cursor`: measured 2026-10-14 (nested sway 1.11) that IPC delivers no motion
while a button is held (only seatop_default rebases), so drags never move; and its
coordinates are layout-BOX relative. motion_absolute here takes box-relative x/y and the
box extent (DESK's box starts at 2103,786), which pointer.Pointer computes from get_outputs."""
from __future__ import annotations

import struct
import time

from .wire import Wire, fixed

BUTTONS = {"left": 272, "right": 273, "middle": 274, "1": 272, "2": 274, "3": 273}


def _t() -> int:
    return int(time.monotonic() * 1000) & 0xFFFFFFFF


class VirtualPointer:
    def __init__(self, wire: Wire) -> None:
        self.w = wire
        mgr = wire.bind("zwlr_virtual_pointer_manager_v1")
        self.ptr = wire.new_id()
        wire.send(mgr, 0, struct.pack("=II", 0, self.ptr))     # create_virtual_pointer(seat=null)
        wire.sync()
        self.held: set[int] = set()

    def motion_abs(self, x: int, y: int, ext_w: int, ext_h: int) -> None:
        self.w.send(self.ptr, 1, struct.pack("=IIIII", _t(), max(0, x), max(0, y), ext_w, ext_h))
        self.w.send(self.ptr, 4)                                 # frame

    def button(self, btn: int, pressed: bool) -> None:
        self.w.send(self.ptr, 2, struct.pack("=III", _t(), btn, 1 if pressed else 0))
        self.w.send(self.ptr, 4)
        (self.held.add if pressed else self.held.discard)(btn)

    def scroll(self, notches: int, horizontal: bool = False) -> None:
        # one notch = axis_discrete 1 + axis 15 + frame (wlroots scales discrete to 120ths)
        axis = 1 if horizontal else 0
        self.w.send(self.ptr, 5, struct.pack("=I", 0))           # axis_source wheel
        self.w.send(self.ptr, 7, struct.pack("=II", _t(), axis) + fixed(notches * 15) + struct.pack("=i", notches))
        self.w.send(self.ptr, 4)

    def release_all(self) -> None:
        for b in list(self.held):
            self.button(b, False)

    def sync(self) -> None:
        self.w.sync()

    def destroy(self) -> None:
        try:
            self.release_all()
            self.w.send(self.ptr, 8)                              # destroy
            self.w.sync()
        except OSError:
            pass
