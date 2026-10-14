"""The input broker: keyboard + pointer injection with end-to-end acks and safety guards.
Plan: docs/akunito/plans/sway-input-broker.md (v2.1, audited).

Backends, chosen per session:
  live    uinput keyboard (excluded from keyd, grouped by sway with Diego's) + virtual pointer
  nested  protocol virtual keyboard with the compiled keymap + virtual pointer (e2e sway has
          no libinput devices, so uinput cannot reach it)
Ack: keycode 202 (KEY_F24, no keysym in us(intl),es,pl) is bound in every mode with all 32
Shift/Ctrl/Alt/Super/Mod5 combinations to `nop sway-apps input ack`; the broker presses it with
no modifiers and waits for the binding event: every earlier key of ours was then processed by
sway (one device, in order). Not proof the CLIENT reacted: wait on events/state for that."""
from __future__ import annotations

import json
import os
import re
import select
import time
from typing import Any

from .. import ipc, log
from .. import overview as ov
from .keymap import CHORD_MODS, KEY_F24, Keymap, KeymapError, Stroke, rmlvo_from_config
from .vpointer import BUTTONS, VirtualPointer
from .wire import Wire

_log = log.get("input")

ACK_CMD = "nop sway-apps input ack"
ABORT_CMD = "nop sway-apps input abort"
ACK_TIMEOUT = 1.0
# Measured live on DESK 2026-10-14: sway lists a new uinput device ~56 ms after
# UI_DEV_CREATE and keys written before that are lost; ack latency 1:1 ~0.2 ms.
DEVICE_WAIT = 2.0
MOD_COMBOS = ("Shift", "Control", "Mod1", "Mod4", "Mod5")
DEFAULT_EXCLUDE = ov.SETTINGS_DEFAULTS["exclude"]


class InputError(RuntimeError):
    pass


class Refused(InputError):
    pass


class Aborted(InputError):
    pass


def ack_bindings(modes: list[str]) -> str:
    """Config text of the sentinel + abort bindings (the Nix module generates the same)."""
    lines = []
    combos = [""]
    for m in MOD_COMBOS:
        combos += [c + m + "+" for c in combos]
    body = [f"bindcode --no-repeat --locked --inhibited {c}202 {ACK_CMD}" for c in combos]
    lines += body
    lines.append(f"bindsym --no-repeat Mod4+Control+Mod1+Shift+Pause {ABORT_CMD}")
    for m in modes:
        lines.append(f'mode "{m}" {{')
        lines += ["  " + b for b in body]
        lines.append("}")
    return "\n".join(lines) + "\n"


def screen_locked() -> bool:
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                with open(f"/proc/{pid}/comm") as fh:
                    if fh.read().startswith("swaylock"):
                        return True
            except OSError:
                continue
    return False


def _has_libinput_keyboard(inputs: list[dict[str, Any]]) -> bool:
    return any(i.get("type") == "keyboard" and "libinput" in i for i in inputs)


class Broker:
    def __init__(self, backend: str | None = None, force: bool = False) -> None:
        self.conn = ipc.Connection()
        self.events = ipc.Connection(self.conn.path)
        self.events.subscribe(["binding", "window", "workspace"])
        self.force = force
        inputs = self.conn.inputs()
        self.backend = backend or os.environ.get("SWAY_APPS_INPUT_BACKEND") or (
            "live" if _has_libinput_keyboard(inputs) and os.access("/dev/uinput", os.W_OK) else "nested")
        self.km = Keymap(rmlvo_from_config(self.conn.config()))
        self.wire = Wire()
        self.pointer = VirtualPointer(self.wire)
        self._box: tuple[int, int, int, int] | None = None
        self.held_mods: set[int] = set()
        self.t0 = time.monotonic()
        if self.backend == "live":
            from .uinput import UInputKeyboard
            self.kbd = UInputKeyboard()
        else:
            from .vkeyboard import VirtualKeyboard
            self.kbd = VirtualKeyboard(self.wire, self.km)
        self.ready_ms: float | None = None
        self._seen: list[tuple[str, Any]] = []   # events read while waiting for an ack, kept for wait_for

    # ---- lifecycle -------------------------------------------------------------------
    def close(self) -> None:
        for dev in (self.kbd, self.pointer):
            try:
                dev.destroy()
            except Exception as exc:   # noqa: BLE001 - every device must get its chance
                _log.warning("input device not destroyed cleanly: %s", exc)
        for c in (self.events, self.conn):
            c.close()
        self.wire.close()

    def __enter__(self) -> "Broker":
        return self

    def __exit__(self, *_exc) -> None:
        self.close()

    def ready(self) -> float:
        """First ack after creating the device: proves the whole path (and, live, that sway
        sees the device). Returns ms since the broker started."""
        if self.ready_ms is None:
            if self.backend == "live":
                ident = "%d:%d:%s" % (0x5341, 0x0001, "sway-apps-input")
                end = time.monotonic() + DEVICE_WAIT
                while not any(i.get("identifier") == ident for i in self.conn.inputs()):
                    if time.monotonic() > end:
                        raise InputError("sway never listed the uinput keyboard")
                    time.sleep(0.002)
                if self.kbd.grabbed_by_other():
                    raise InputError("the uinput keyboard is grabbed by another process (keyd not excluding 5341:0001?)")
            self.ack()
            self.ready_ms = round(1000 * (time.monotonic() - self.t0), 1)
        return self.ready_ms

    # ---- events / ack ----------------------------------------------------------------
    def _next_event(self, deadline: float) -> tuple[str, Any] | None:
        left = deadline - time.monotonic()
        if left <= 0:
            return None
        r, _, _ = select.select([self.events.fileno()], [], [], left)
        if not r:
            return None
        name, body = self.events.next_event()
        if name == "binding" and ((body or {}).get("binding") or {}).get("command", "") == ABORT_CMD:
            self.release_all()
            raise Aborted("abort binding pressed")
        return name, body

    def drain(self) -> None:
        while self._next_event(time.monotonic() + 0.0005):
            pass
        self._seen.clear()

    def ack(self, timeout: float = ACK_TIMEOUT) -> float:
        """Press the sentinel and wait for its binding event; ms."""
        state = self.conn.binding_state()
        if state != "default" and not self.force:
            raise Refused(f"sway is in binding mode {state!r}")
        # One press, one binding event: no retry, or a late event would pair with the next ack.
        t = time.monotonic()
        self.kbd.key(KEY_F24, True)
        self.kbd.key(KEY_F24, False)
        if self.backend != "live":
            self.wire.sync()
        deadline = time.monotonic() + timeout
        while (ev := self._next_event(deadline)) is not None:
            name, body = ev
            if name == "binding" and ((body or {}).get("binding") or {}).get("command", "") == ACK_CMD:
                return round(1000 * (time.monotonic() - t), 2)
            self._seen.append(ev)
        raise InputError("no ack from sway (shortcuts inhibited, locked, unknown modifier held, or not bound)")

    def wait_for(self, spec: str, timeout: float) -> dict[str, Any]:
        """spec 'window:focus', 'workspace:focus', 'binding:<substring>', 'window:new'..."""
        kind, _, what = spec.partition(":")
        deadline = time.monotonic() + timeout

        def events():
            while self._seen:
                yield self._seen.pop(0)
            while (e := self._next_event(deadline)) is not None:
                yield e
        for ev in events():
            name, body = ev
            body = body or {}
            if name != kind:
                continue
            if kind == "binding":
                cmd = (body.get("binding") or {}).get("command", "")
                if what in cmd and cmd not in (ACK_CMD,):
                    return {"event": name, "command": cmd}
            elif not what or body.get("change") == what:
                c = body.get("container") or body.get("current") or {}
                return {"event": name, "change": body.get("change"), "id": c.get("id"),
                        "name": c.get("app_id") or c.get("name")}
        raise InputError(f"timed out waiting for {spec}")

    # ---- guards ------------------------------------------------------------------------
    def guard(self, expect_focus: str | None = None) -> ov.Card | None:
        if self.force:
            return None
        if self.backend == "live" and screen_locked():
            raise Refused("the screen is locked")
        views = ov.build(self.conn.tree())
        f = ov.focused_card(views)
        if expect_focus:
            ok = f is not None and (str(f.id) == expect_focus or re.search(expect_focus, f.app_id or ""))
            if not ok:
                raise Refused(f"focus is on {f.app_id if f else None!r} (con {f.id if f else None}), expected {expect_focus!r}")
        if f is not None and f.fullscreen:
            raise Refused(f"focused window {f.app_id!r} is fullscreen")
        if f is not None and ov.exclusion_matcher({"exclude": DEFAULT_EXCLUDE})(f.app_id):
            raise Refused(f"focused window {f.app_id!r} is excluded (game / password manager)")
        if self.backend == "live" and f is None and not any(w.get("focused") for w in self.conn.workspaces()):
            raise Refused("no view or workspace focused")
        return f

    # ---- keyboard ------------------------------------------------------------------------
    def group(self) -> int:
        for i in self.conn.inputs():
            if i.get("type") == "keyboard" and "xkb_active_layout_index" in i and "libinput" in i:
                return int(i["xkb_active_layout_index"])
        for i in self.conn.inputs():
            if i.get("type") == "keyboard" and "xkb_active_layout_index" in i:
                return int(i["xkb_active_layout_index"])
        return 0

    def strokes(self, strokes: list[Stroke]) -> None:
        for st in strokes:
            for m in st.mods:
                self.kbd.key(m, True)
            self.kbd.key(st.key, True)
            self.kbd.key(st.key, False)
            for m in reversed(st.mods):
                self.kbd.key(m, False)

    def key(self, chord: str, ack: bool = True) -> dict[str, Any]:
        st = self.km.chord(chord, self.group())
        self.strokes(st)
        return {"ack_ms": self.ack() if ack else None}

    def type(self, text: str, ack: bool = True) -> dict[str, Any]:
        st = self.km.text(text, self.group())
        self.strokes(st)
        return {"keys": len(st), "ack_ms": self.ack() if ack else None}

    def hold(self, chord_mods: str, down: bool) -> None:
        """Hold modifier keys across pointer actions ('Hyper', 'Mod4+Shift')."""
        keys: list[int] = []
        for p in [p for p in chord_mods.split("+") if p]:
            if p.lower() not in CHORD_MODS:
                raise KeymapError(f"unknown modifier {p!r}")
            keys += [k for k in CHORD_MODS[p.lower()] if k not in keys]
        for k in (keys if down else reversed(keys)):
            self.kbd.key(k, down)
            (self.held_mods.add if down else self.held_mods.discard)(k)
        # Keys travel uinput -> libinput, the pointer a Wayland socket: no ordering between
        # them. Measured live 2026-10-14: a Super+drag started before sway had the Super, so
        # the window did not move. The ack (bound with every modifier) closes the gap.
        self.ack()

    # ---- pointer -----------------------------------------------------------------------
    def box(self) -> tuple[int, int, int, int]:
        if self._box is None:
            rs = [o["rect"] for o in self.conn.outputs() if o.get("active")]
            x0, y0 = min(r["x"] for r in rs), min(r["y"] for r in rs)
            self._box = (x0, y0, max(r["x"] + r["width"] for r in rs) - x0, max(r["y"] + r["height"] for r in rs) - y0)
        return self._box

    def resolve(self, target: str) -> tuple[int, int]:
        """Layout point of 'x,y' | 'con:ID[:dx,dy]' | 'output:NAME:x,y' | 'ov-card:ID'."""
        if re.fullmatch(r"-?\d+,-?\d+", target):
            x, y = target.split(",")
            return int(x), int(y)
        kind, _, rest = target.partition(":")
        if kind == "con":
            cid, _, off = rest.partition(":")
            node = _find(self.conn.tree(), int(cid))
            if node is None:
                raise InputError(f"no container {cid}")
            r = node["rect"]
            if off:
                dx, dy = (int(v) for v in off.split(","))
                return r["x"] + dx, r["y"] + dy
            return r["x"] + r["width"] // 2, r["y"] + r["height"] // 2
        if kind == "output":
            name, _, xy = rest.partition(":")
            o = next((o for o in self.conn.outputs() if o["name"] == name), None)
            if o is None:
                raise InputError(f"no output {name}")
            dx, dy = (int(v) for v in (xy or "0,0").split(","))
            return o["rect"]["x"] + dx, o["rect"]["y"] + dy
        if kind == "ov-card":
            st = ov.request("state")
            b = (st.get("bounds") or {}).get(rest)
            if not b:
                raise InputError(f"overview card {rest} not shown")
            out, x, y, w, h = b
            o = next(o for o in self.conn.outputs() if o["name"] == out)
            return o["rect"]["x"] + x + w // 2, o["rect"]["y"] + y + h // 2
        raise InputError(f"bad target {target!r}")

    def move(self, lx: int, ly: int) -> None:
        x0, y0, w, h = self.box()
        self.pointer.motion_abs(lx - x0, ly - y0, w, h)

    def click(self, target: str, button: str = "left", count: int = 1) -> dict[str, Any]:
        x, y = self.resolve(target)
        b = BUTTONS[button]
        self.move(x, y)
        for _ in range(count):
            self.pointer.button(b, True)
            self.pointer.button(b, False)
        self.pointer.sync()
        return {"at": [x, y]}

    def drag(self, src: str, dst: str, steps: int = 12, ms: int = 120, hold_ms: int = 0,
             button: str = "left") -> dict[str, Any]:
        (x0, y0), (x1, y1) = self.resolve(src), self.resolve(dst)
        b = BUTTONS[button]
        self.move(x0, y0)
        self.pointer.button(b, True)
        self.pointer.sync()
        if hold_ms:
            time.sleep(hold_ms / 1000)
        for i in range(1, steps + 1):
            self.move(x0 + (x1 - x0) * i // steps, y0 + (y1 - y0) * i // steps)
            self.pointer.sync()
            time.sleep(ms / 1000 / steps)
        self.pointer.button(b, False)
        self.pointer.sync()
        return {"from": [x0, y0], "to": [x1, y1]}

    def scroll(self, target: str, notches: int) -> dict[str, Any]:
        x, y = self.resolve(target)
        self.move(x, y)
        self.pointer.scroll(notches)
        self.pointer.sync()
        return {"at": [x, y]}

    def release_all(self) -> None:
        for dev in (self.kbd, self.pointer):
            try:
                dev.release_all()
            except OSError:
                pass
        self.held_mods.clear()


def _find(node: dict[str, Any], cid: int) -> dict[str, Any] | None:
    if node.get("id") == cid:
        return node
    for c in (node.get("nodes") or []) + (node.get("floating_nodes") or []):
        r = _find(c, cid)
        if r is not None:
            return r
    return None


def panic() -> dict[str, Any]:
    """Release buttons 1-3 and every modifier, from fresh devices, post-mortem: a SIGKILLed
    broker's uinput keys are released by the kernel on disconnect, its pointer buttons are not."""
    conn = ipc.Connection()
    done = []
    for b in ("button1", "button2", "button3"):
        conn.command(f"seat seat0 cursor release {b}")
        done.append(b)
    try:
        w = Wire()
        p = VirtualPointer(w)
        for b in (272, 273, 274):
            p.button(b, False)
        p.destroy()
        w.close()
    except Exception as exc:   # noqa: BLE001
        _log.warning("panic: virtual pointer: %s", exc)
    conn.close()
    return {"released": done}


def dumps(d: dict[str, Any]) -> str:
    return json.dumps(d, separators=(",", ":"))
