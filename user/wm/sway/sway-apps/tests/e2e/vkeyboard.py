"""Persistent virtual keyboard (zwp_virtual_keyboard_v1) in pure Python, for held modifiers.

The nested sway runs with WLR_LIBINPUT_NO_DEVICES, so it has no keyboard: this one
becomes the seat keyboard, and sway reads floating_modifier and mouse-binding
modifiers from it. Reads commands on stdin, answers "ok" after a display sync:
  mods MASK     depressed modifier mask (Shift 1, Control 4, Mod1 8, Mod4 64); 0 releases
"""
from __future__ import annotations

import os
import socket
import struct
import sys

from vpointer import Wire, s_arg

KEYMAP = b"""xkb_keymap {
xkb_keycodes "e2e" { minimum = 8; maximum = 255; <LFSH> = 50; <LCTL> = 37; <LALT> = 64; <LWIN> = 133; };
xkb_types "e2e" { type "ONE_LEVEL" { modifiers = none; map[none] = Level1; level_name[Level1] = "Any"; }; };
xkb_compatibility "e2e" { };
xkb_symbols "e2e" {
  key <LFSH> { [ Shift_L ] }; key <LCTL> { [ Control_L ] }; key <LALT> { [ Alt_L ] }; key <LWIN> { [ Super_L ] };
  modifier_map Shift { <LFSH> }; modifier_map Control { <LCTL> }; modifier_map Mod1 { <LALT> }; modifier_map Mod4 { <LWIN> };
};
};
\0"""


def main() -> int:
    w = Wire()
    reg = w.new_id()
    w.send(1, 1, struct.pack("=I", reg))
    cb = w.new_id()
    w.send(1, 0, struct.pack("=I", cb))
    names: dict[str, tuple[int, int]] = {}
    while True:
        obj, op, data = w.read_event()
        if obj == reg and op == 0:
            name, ln = struct.unpack("=II", data[:8])
            iface = data[8:8 + ln - 1].decode()
            off = 8 + ln + (-ln % 4)
            names.setdefault(iface, (name, struct.unpack("=I", data[off:off + 4])[0]))
        elif obj == cb and op == 0:
            break
    if "zwp_virtual_keyboard_manager_v1" not in names or "wl_seat" not in names:
        print("no zwp_virtual_keyboard_manager_v1 / wl_seat", flush=True)
        return 1
    seat = w.new_id()
    w.send(reg, 0, struct.pack("=I", names["wl_seat"][0]) + s_arg("wl_seat") + struct.pack("=II", 1, seat))
    mgr = w.new_id()
    w.send(reg, 0, struct.pack("=I", names["zwp_virtual_keyboard_manager_v1"][0])
           + s_arg("zwp_virtual_keyboard_manager_v1") + struct.pack("=II", 1, mgr))
    kbd = w.new_id()
    w.send(mgr, 0, struct.pack("=II", seat, kbd))                  # create_virtual_keyboard(seat, id)
    fd = os.memfd_create("e2e-keymap")
    os.write(fd, KEYMAP)
    payload = struct.pack("=II", 1, len(KEYMAP))                   # keymap(format xkb_v1, fd, size)
    msg = struct.pack("=II", kbd, ((8 + len(payload)) << 16) | 0) + payload
    w.s.sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, struct.pack("=i", fd))])
    os.close(fd)
    w.sync()
    print("ready", flush=True)
    for line in sys.stdin:
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "mods":
            w.send(kbd, 2, struct.pack("=IIII", int(parts[1]), 0, 0, 0))  # modifiers
        w.sync()
        print("ok", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
