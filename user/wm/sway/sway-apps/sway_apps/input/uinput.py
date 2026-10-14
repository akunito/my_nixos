"""uinput keyboard - the live keyboard backend.

Device 5341:0001 "sway-apps-input", excluded from keyd (system/wm/keyd.nix) so sway sees it
as a libinput keyboard and groups it with keyd's virtual keyboard (keyboard_grouping smart:
same keymap + repeat config): Diego's keymap, one modifier state, no keymap resend
(verified in sway 1.11 source by the 2026-10-14 audit). No EV_REP: Wayland repeat is
client side. KEY_ESC..KEY_D are declared so udev tags it ID_INPUT_KEYBOARD."""
from __future__ import annotations

import errno
import fcntl
import glob
import os
import struct
import time

VENDOR, PRODUCT = 0x5341, 0x0001
NAME = b"sway-apps-input"
EV_SYN, EV_KEY, SYN_REPORT, BUS_USB = 0, 1, 0, 0x03
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_SETUP = 0x405C5503      # _IOW('U', 3, struct uinput_setup) - 92 bytes
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
UI_GET_SYSNAME_64 = 0x8040552C  # _IOC(_IOC_READ, 'U', 44, 64)
EVIOCGRAB = 0x40044590
_EV = struct.Struct("=qqHHi")   # struct input_event on 64-bit: timeval + type + code + value


class UInputKeyboard:
    def __init__(self, keys: range | set[int] = range(1, 249), ids: tuple[int, int] = (VENDOR, PRODUCT),
                 name: bytes = NAME) -> None:
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        self.held: set[int] = set()
        try:
            fcntl.ioctl(self.fd, UI_SET_EVBIT, EV_KEY)
            for k in set(keys) | set(range(1, 33)):      # KEY_ESC..KEY_D for udev's keyboard tag
                fcntl.ioctl(self.fd, UI_SET_KEYBIT, k)
            fcntl.ioctl(self.fd, UI_DEV_SETUP, struct.pack("=HHHH80sI", BUS_USB, ids[0], ids[1], 1, name, 0))
            fcntl.ioctl(self.fd, UI_DEV_CREATE)
        except OSError:
            os.close(self.fd)
            raise
        self.created = time.monotonic()

    def _write(self, etype: int, code: int, value: int) -> None:
        os.write(self.fd, _EV.pack(0, 0, etype, code, value))

    def key(self, code: int, pressed: bool) -> None:
        self._write(EV_KEY, code, 1 if pressed else 0)
        self._write(EV_SYN, SYN_REPORT, 0)
        (self.held.add if pressed else self.held.discard)(code)

    def release_all(self) -> None:
        for k in list(self.held):
            self.key(k, False)

    def event_node(self, timeout: float = 2.0) -> str | None:
        """/dev/input/eventN of this device (udev creates it asynchronously)."""
        buf = bytearray(64)
        fcntl.ioctl(self.fd, UI_GET_SYSNAME_64, buf)
        sysname = buf.split(b"\0", 1)[0].decode()
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            nodes = glob.glob(f"/sys/devices/virtual/input/{sysname}/event*")
            if nodes and os.path.exists(f"/dev/input/{os.path.basename(nodes[0])}"):
                return f"/dev/input/{os.path.basename(nodes[0])}"
            time.sleep(0.005)
        return None

    def grabbed_by_other(self) -> bool | None:
        """EVIOCGRAB probe: True = someone (keyd) holds it, False = free, None = unknown."""
        node = self.event_node()
        if node is None:
            return None
        try:
            fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        except OSError:
            return None
        try:
            fcntl.ioctl(fd, EVIOCGRAB, 1)
            fcntl.ioctl(fd, EVIOCGRAB, 0)
            return False
        except OSError as exc:
            return True if exc.errno == errno.EBUSY else None
        finally:
            os.close(fd)

    def destroy(self) -> None:
        if self.fd < 0:
            return
        try:
            self.release_all()
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)   # the kernel also simulates key-ups on disconnect
        except OSError:
            pass
        os.close(self.fd)
        self.fd = -1
