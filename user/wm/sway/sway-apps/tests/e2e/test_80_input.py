"""sway-apps input on the nested backend (virtual keyboard with Diego's compiled keymap +
virtual pointer): ready/ack, chords reaching bindings, AltGr/dead-key text reaching a GTK
client, drags that actually move, the fullscreen guard. The live backend (uinput) needs
libinput devices and is checked by tests/live, never here."""
from __future__ import annotations

import json
import os
import subprocess

from harness import ROOT, PYTHON, E2EFailure, Nested
from sway_apps.input.broker import ack_bindings

KEYMAP = 'input type:keyboard {\n  xkb_layout "us,es,pl"\n  xkb_variant "intl,,"\n}\n'
CFG = KEYMAP + ack_bindings(["resize"]) + (
    'mode "resize" {\n  bindsym Escape mode default\n}\n'
    "bindsym Mod4+Control+Mod1+Shift+9 nop e2e hyper-shift-9\n"
    "bindsym Mod4+Control+Mod1+r mode resize\n")
XKB = os.environ.get("SWAY_APPS_XKBCOMMON", "")


def run_input(s: Nested, *args: str, ok: bool = True) -> dict:
    env = {**s.env, "PYTHONPATH": str(ROOT), "SWAY_APPS_INPUT_BACKEND": "nested"}
    if XKB:
        env["SWAY_APPS_XKBCOMMON"] = XKB
    r = subprocess.run([PYTHON, "-m", "sway_apps", "input", *args], env=env, cwd=str(ROOT),
                       capture_output=True, text=True, timeout=30)
    try:
        out = json.loads(r.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError):
        raise E2EFailure(f"input {args}: no JSON (rc {r.returncode}) {r.stderr[-400:]}")
    if out.get("ok") != ok:
        raise E2EFailure(f"input {args}: {out}")
    return out


def case_probe_ready_and_acks():
    with Nested(outputs=1, config=CFG) as s:
        s.client("e2e.a", floating=True)
        out = run_input(s, "probe", "-n", "20")
        if out["backend"] != "nested" or out["ack_ms"]["n"] != 20 or out["ack_ms"]["p95"] > 50:
            raise E2EFailure(f"probe {out}")


def case_chord_reaches_a_binding_and_ack_works_in_modes():
    with Nested(outputs=1, config=CFG) as s:
        s.client("e2e.a", floating=True)
        run_input(s, "--until", "binding:hyper-shift-9", "key", "Hyper+Shift+9")
        run_input(s, "--force", "key", "Hyper+r")            # into mode "resize": guard refuses the next
        out = run_input(s, "key", "Escape", ok=False)
        if "binding mode" not in out["error"]:
            raise E2EFailure(f"guard in resize mode: {out}")
        run_input(s, "--force", "key", "Escape")             # the ack is bound in "resize" too


def case_text_with_altgr_levels_reaches_the_client():
    with Nested(outputs=1, config=CFG) as s:
        a = s.client("e2e.a", floating=True)
        a.cmd("focus")
        text = "don't é \"x\" ñ ü Hola"
        run_input(s, "--expect-focus", "e2e.a", "type", text)
        s.wait(lambda: "".join(eval(l[5:]) for l in a.log_text().splitlines() if l.startswith("text ")) == text,
               f"client received {text!r}", 5)


def case_drag_moves_and_click_lands():
    with Nested(outputs=1, config=CFG) as s:
        a = s.client("e2e.a", size="400x300", floating=True)
        a.cmd("move position 100 100")
        s.wait(lambda: a.rect()["x"] == 100, "float moved")
        run_input(s, "click", "con:%d:100,100" % a.con_id)
        s.wait(lambda: "release 1" in a.log_text(), "click logged")
        a.clear_log()
        run_input(s, "drag", "con:%d:50,50" % a.con_id, "con:%d:250,150" % a.con_id, "--hold-ms", "300")
        s.wait(lambda: "release 1" in a.log_text(), "drag release logged")
        p = next(l.split() for l in a.log_text().splitlines() if l.startswith("press"))
        r = next(l.split() for l in a.log_text().splitlines() if l.startswith("release"))
        if abs(int(r[2]) - int(p[2])) < 150:
            raise E2EFailure(f"the drag did not move: {a.log_text()!r}")


def case_guard_refuses_fullscreen_unless_forced():
    with Nested(outputs=1, config=CFG) as s:
        s.client("e2e.game", fullscreen=True)
        s.wait(lambda: (s.focused() or {}).get("fullscreen_mode") == 1, "game fullscreen")
        out = run_input(s, "key", "q", ok=False)
        if "fullscreen" not in out["error"]:
            raise E2EFailure(f"guard: {out}")
        run_input(s, "--force", "key", "q")
