"""zwp_virtual_keyboard_v1 with Diego's compiled keymap - the nested (e2e) keyboard backend.
A nested sway has no libinput devices, so uinput cannot reach it. Protocol virtual
keyboards are never grouped (sway marks them is_virtual) - fine there, it is the only one.
wlroots does not update its xkb state from our keys, so KeyState computes `modifiers`."""
from __future__ import annotations

import os
import struct
import time

from .keymap import Keymap, KeyState
from .wire import Wire


class VirtualKeyboard:
    def __init__(self, wire: Wire, km: Keymap) -> None:
        self.w = wire
        seat = wire.bind("wl_seat", 1)
        mgr = wire.bind("zwp_virtual_keyboard_manager_v1")
        self.kbd = wire.new_id()
        wire.send(mgr, 0, struct.pack("=II", seat, self.kbd))
        data = km.as_string() + b"\0"
        fd = os.memfd_create("sway-apps-keymap", os.MFD_CLOEXEC)
        os.write(fd, data)
        wire.send_fd(self.kbd, 0, struct.pack("=II", 1, len(data)), fd)   # keymap(xkb_v1, fd, size)
        os.close(fd)
        wire.sync()
        self.state = KeyState(km)
        self.held: set[int] = set()

    def key(self, code: int, pressed: bool) -> None:
        t = int(time.monotonic() * 1000) & 0xFFFFFFFF
        self.w.send(self.kbd, 1, struct.pack("=III", t, code, 1 if pressed else 0))
        self.w.send(self.kbd, 2, struct.pack("=IIII", *self.state.key(code, pressed)))
        (self.held.add if pressed else self.held.discard)(code)

    def release_all(self) -> None:
        for k in list(self.held):
            self.key(k, False)

    def destroy(self) -> None:
        try:
            self.release_all()
            self.w.send(self.kbd, 3)
            self.w.sync()
        except OSError:
            pass
