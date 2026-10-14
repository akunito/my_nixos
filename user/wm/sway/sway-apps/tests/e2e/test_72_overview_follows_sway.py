"""Overview + sway bindings (2026-10-14, Diego): while open, the workspace bindings go
through scripts/overview-selected.sh (as in swayfx-config.nix), so Hyper+Q/W/N switch
workspace from the SELECTED window and Hyper+Shift+N move it; the panels re-sync to
sway. Navigation never moves sway's focus. Cards drag onto workspace columns."""
from __future__ import annotations

import time

import os
from pathlib import Path

from harness import E2EFailure, Nested
from sway_apps import overview as ovm
from test_70_overview import BIND, HYPER, OUTS, SHIFT, Keys, Overview, layout

WRAP = str(Path(__file__).resolve().parents[3] / "scripts" / "overview-selected.sh")
CFG = BIND + (f"\nbindsym Mod4+Control+Mod1+w exec {WRAP} swaymsg workspace next_on_output"
              f"\nbindsym Mod4+Control+Mod1+2 exec {WRAP} swaymsg workspace 2"
              f"\nbindsym Mod4+Control+Mod1+1 exec {WRAP} swaymsg workspace 5"
              f"\nbindsym Mod4+Control+Mod1+Shift+2 exec {WRAP} swaymsg move container to workspace 2")
# swaymsg for the wrapper and the bindings: next to the sway under test
ENV = {"PATH": os.pathsep.join([os.path.dirname(os.environ.get("E2E_SWAY") or "/run/current-system/sw/bin/sway"),
                                os.environ.get("PATH", "")])}


def sway_focus(s: Nested) -> str | None:
    """sway's focused window even while the overview's layer holds the keyboard (no node
    has focused=true then; the focus stacks still say)."""
    c = ovm.focused_card(ovm.build(s.tree()))
    return c.app_id if c else None


def chord(keys: Keys, key: str, shift: bool = False) -> None:
    keys.mods(HYPER | (SHIFT if shift else 0))
    keys.key(key)
    keys.mods(0)


def focused_ws(st: dict) -> list[str]:
    return [g["workspace"] for o in st["outputs"].values() for g in o["groups"] if g["focused"]]


def column(st: dict, ws: str) -> list[str]:
    return next([c["app_id"] for c in g["cards"]] for o in st["outputs"].values() for g in o["groups"] if g["workspace"] == ws)


def case_navigation_writes_the_selection_and_leaves_sway_focus_alone():
    with Nested(outputs=OUTS, config=CFG, env=ENV) as s:
        w = layout(s)
        o = Overview(s)
        keys = Keys(s)
        sel = Path(s.env["XDG_RUNTIME_DIR"]) / "sway-apps-overview.sel"
        keys.hyper_tab()
        o.wait_open()
        s.wait(lambda: sel.exists() and sel.read_text().strip() == str(w["a"].con_id), "selection file = e2e.a at open")
        keys.key("Right")                         # ws 1 [a, b] -> ws 2 [c] (hidden)
        s.wait(lambda: sel.read_text().strip() == str(w["c"].con_id), "selection file follows to e2e.c")
        if sway_focus(s) != "e2e.a" or focused_ws(o.state()) != ["1"]:
            raise E2EFailure(f"navigation moved sway's focus: {sway_focus(s)} {focused_ws(o.state())}")
        keys.key("Escape")
        o.wait_closed()
        s.wait(lambda: not sel.exists(), "selection file removed on close")
        s.wait(lambda: (s.focused() or {}).get("app_id") == "e2e.a", "focus still on e2e.a after Escape")


def case_hyper_workspace_keys_resync_the_open_overview():
    with Nested(outputs=OUTS, config=CFG, env=ENV) as s:
        w = layout(s)
        o = Overview(s)
        keys = Keys(s)
        keys.hyper_tab()
        o.wait_open()
        keys.key("Down")                          # select e2e.b: the switch starts from it
        chord(keys, "2")
        s.wait(lambda: focused_ws(o.state()) == ["2"] and o.state()["selected"] == w["c"].con_id,
               "Hyper+2: ws 2 focused and e2e.c selected in the overview")
        chord(keys, "1")                          # bound to an EMPTY workspace 5
        s.wait(lambda: focused_ws(o.state()) == ["5"] and o.state()["selected"] is None and column(o.state(), "5") == [],
               "Hyper+1: empty ws 5 shown as the focused column, nothing selected")
        chord(keys, "w")                          # next_on_output: back among the windows
        s.wait(lambda: focused_ws(o.state()) not in ([], ["5"]), "Hyper+W moved on from ws 5")
        if not o.state()["open"]:
            raise E2EFailure("a workspace binding closed the overview")
        chord(keys, "2")
        s.wait(lambda: o.state()["selected"] == w["c"].con_id, "Hyper+2 again: e2e.c selected")
        keys.key("Escape")                        # a binding ran: closing keeps where the user went
        o.wait_closed()
        time.sleep(0.3)
        if (s.focused() or {}).get("app_id") != "e2e.c":
            raise E2EFailure(f"Escape undid the user's workspace switch: focus on {(s.focused() or {}).get('app_id')}")


def case_hyper_shift_moves_the_selected_window():
    with Nested(outputs=OUTS, config=CFG, env=ENV) as s:
        w = layout(s)
        o = Overview(s)
        keys = Keys(s)
        keys.hyper_tab()
        o.wait_open()
        keys.key("Down")                          # a -> b: selection only
        s.wait(lambda: o.state()["selected"] == w["b"].con_id, "e2e.b selected")
        chord(keys, "2", shift=True)
        try:
            s.wait(lambda: column(o.state(), "2") == ["e2e.c", "e2e.b"] and column(o.state(), "1") == ["e2e.a"],
                   "Hyper+Shift+2 moved e2e.b (not e2e.a) to ws 2, panels re-synced", 3)
        except E2EFailure as exc:
            st = o.state()
            raise E2EFailure(f"{exc}: " + str({g["workspace"]: [c["app_id"] for c in g["cards"]]
                                                for out in st["outputs"].values() for g in out["groups"]})
                             + f" sway={[(x['name'], x['focused']) for x in s.workspaces()]}")
        if not o.state()["open"]:
            raise E2EFailure("the move closed the overview")


def case_drag_card_onto_another_workspace_column():
    with Nested(outputs=OUTS, config=CFG, env=ENV) as s:
        w = layout(s)
        o = Overview(s)
        o.cli("show")
        st = o.wait_open()
        ob, ax, ay, aw, ah = st["bounds"][str(w["a"].con_id)]
        db, dx, dy, dw, dh = st["bounds"][str(w["d"].con_id)]
        if (ob, db) != ("HEADLESS-1", "HEADLESS-2"):
            raise E2EFailure(f"cards on {ob}/{db}")
        x0, y0 = ax + aw // 2, ay + ah // 2
        x1, y1 = OUTS[0][0] + dx + dw // 2, dy + dh // 2
        s.press(x0, y0)
        for i in range(1, 21):                    # past the drag threshold, across the output edge
            s.pointer_to(x0 + (x1 - x0) * i // 20, y0 + (y1 - y0) * i // 20)
            time.sleep(0.02)
        s.release()
        try:
            s.wait(lambda: column(o.state(), "11") == ["e2e.d", "e2e.a"], "e2e.a dropped into ws 11 on the other output", 3)
        except E2EFailure as exc:
            st = o.state()
            raise E2EFailure(f"{exc}: open={st['open']} " + str({g['workspace']: [c['app_id'] for c in g['cards']]
                                                                 for out in st['outputs'].values() for g in out['groups']}))
        if not o.state()["open"]:
            raise E2EFailure("the drop closed the overview (or activated the card)")
