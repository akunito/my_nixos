"""`sway-apps input`: keyboard + pointer injection for Claude's hand tests and the e2e suite.
Plan: docs/akunito/plans/sway-input-broker.md. Every key action ends with an ack (the
bindcode-202 sentinel); pointer actions with a Wayland roundtrip; `--until` waits for the
effect on sway (window/workspace/binding events). Refuses on lock screen, fullscreen,
excluded apps, non-default binding mode, or an unexpected focus, unless --force."""
from __future__ import annotations

import shlex
import signal
import statistics
import sys
import time

from .. import log

_log = log.get("input")

SETTINGS_KEY = "input"
SETTINGS_DEFAULTS: dict = {}   # nothing tunable yet: the guards are fixed on purpose


def setup_watch(reg) -> None:
    # The broker reads its own ack/abort binding events; this keeps the watch daemon from
    # logging "no handler for verb 'input'" on every ack (seen live 2026-10-14).
    reg.verb("input", lambda _args, _ctx: None)


def register_cli(sub) -> None:
    p = sub.add_parser("input", help="inject keyboard/pointer input (hand tests, e2e)")
    p.add_argument("--force", action="store_true", help="skip the safety guards")
    p.add_argument("--backend", choices=("live", "nested"), help="default: live when sway has libinput keyboards")
    p.add_argument("--expect-focus", metavar="CON_ID|APP_ID_RE", help="refuse unless the focused window matches")
    p.add_argument("--until", metavar="EVENT[:WHAT]", help="after the action wait for window:focus, workspace:focus, binding:<text>…")
    p.add_argument("--timeout", type=float, default=3.0, help="for --until (s)")
    s = p.add_subparsers(dest="verb", required=True)
    k = s.add_parser("key", help="press a chord: 'Hyper+Shift+9', 'Super+Return', 'Escape'")
    k.add_argument("chord", nargs="+")
    t = s.add_parser("type", help="type text with the active layout (AltGr levels, dead keys)")
    t.add_argument("text")
    c = s.add_parser("click", help="TARGET: x,y | con:ID[:dx,dy] | output:NAME:x,y | ov-card:ID")
    c.add_argument("target")
    c.add_argument("--button", default="left", choices=("left", "right", "middle"))
    c.add_argument("--count", type=int, default=1)
    c.add_argument("--mods", default="", help="modifiers held during the click, e.g. Mod4 or Hyper")
    d = s.add_parser("drag", help="press on SRC, move to DST in steps, release")
    d.add_argument("src")
    d.add_argument("dst")
    d.add_argument("--steps", type=int, default=12)
    d.add_argument("--ms", type=int, default=120)
    d.add_argument("--hold-ms", type=int, default=0, help="rest after the press (a hand does)")
    d.add_argument("--button", default="left", choices=("left", "right", "middle"))
    d.add_argument("--mods", default="", help="modifiers held during the drag (floating_modifier: Mod1)")
    sc = s.add_parser("scroll", help="wheel notches at TARGET (+ down, - up)")
    sc.add_argument("target")
    sc.add_argument("notches", type=int)
    m = s.add_parser("move", help="move the pointer to TARGET")
    m.add_argument("target")
    pr = s.add_parser("probe", help="backend, layout group, grab status, ready + ack latency")
    pr.add_argument("-n", type=int, default=20)
    s.add_parser("panic", help="release pointer buttons and modifiers (after a crashed run)")
    s.add_parser("serve", help="keep one device; read commands (same syntax as the CLI) on stdin, JSON out")
    p.set_defaults(func=_cmd)


def _run(b, a) -> dict:
    v = a.verb
    b.drain()          # --until must only see what THIS action caused
    if v in ("key", "type", "click", "drag", "scroll", "move"):
        b.guard(a.expect_focus)
    if v == "key":
        out = {"chords": []}
        for ch in a.chord:
            out["chords"].append(b.key(ch))
    elif v == "type":
        out = b.type(a.text)
    elif v in ("click", "drag"):
        if a.mods:
            b.hold(a.mods, True)
        try:
            out = (b.click(a.target, a.button, a.count) if v == "click"
                   else b.drag(a.src, a.dst, a.steps, a.ms, a.hold_ms, a.button))
        finally:
            if a.mods:
                b.hold(a.mods, False)
    elif v == "scroll":
        out = b.scroll(a.target, a.notches)
    elif v == "move":
        x, y = b.resolve(a.target)
        b.move(x, y)
        b.pointer.sync()
        out = {"at": [x, y]}
    elif v == "probe":
        ready = b.ready()
        acks = [b.ack() for _ in range(a.n)]
        acks.sort()
        out = {"backend": b.backend, "group": b.group(), "rmlvo": b.km.rmlvo, "ready_ms": ready,
               "ack_ms": {"median": statistics.median(acks), "p95": acks[max(0, int(len(acks) * 0.95) - 1)],
                          "max": acks[-1], "n": len(acks)},
               "grabbed_by_other": b.kbd.grabbed_by_other() if b.backend == "live" else None}
    else:
        raise ValueError(v)
    if getattr(a, "until", None):
        out["until"] = b.wait_for(a.until, a.timeout)
    return out


def _cmd(a) -> int:
    from .broker import Broker, InputError, KeymapError, dumps, panic
    if a.verb == "panic":
        print(dumps({"ok": True, **panic()}))
        return 0
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    t = time.monotonic()
    try:
        with Broker(a.backend, a.force) as b:
            b.drain()
            if a.verb != "probe":
                b.ready()
            if a.verb == "serve":
                return _serve(b, a)
            out = _run(b, a)
    except (InputError, KeymapError, OSError, ValueError) as exc:   # ValueError: a malformed target
        print(dumps({"ok": False, "error": str(exc), "ms": round(1000 * (time.monotonic() - t), 1)}))
        return 1
    print(dumps({"ok": True, **out, "ms": round(1000 * (time.monotonic() - t), 1)}))
    return 0


def _serve(b, a) -> int:
    """One command per line, CLI syntax without the 'input' prefix; one JSON line back."""
    import argparse
    from .broker import InputError, KeymapError, dumps
    parser = argparse.ArgumentParser(prog="serve", exit_on_error=False)
    sub = parser.add_subparsers(dest="top")
    register_cli(sub)
    print(dumps({"ok": True, "ready": True, "backend": b.backend, "ready_ms": b.ready_ms}), flush=True)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        t = time.monotonic()
        try:
            args = parser.parse_args(["input", *shlex.split(line)])
            b.force = args.force or a.force
            if args.verb in ("serve", "panic"):
                raise InputError(f"{args.verb} not allowed inside serve")
            out = {"ok": True, **_run(b, args)}
        except (InputError, KeymapError, OSError, ValueError, SystemExit, argparse.ArgumentError) as exc:
            out = {"ok": False, "error": str(exc)}
        out["ms"] = round(1000 * (time.monotonic() - t), 1)
        print(dumps(out), flush=True)
    return 0
