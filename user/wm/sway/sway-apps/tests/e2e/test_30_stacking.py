"""Window stacking (patches/sway-window-stacking.patch): peek, pin band, z raise|lower,
window:move for floating drag/resize. Needs a sway built with the patch (E2E_SWAY).

Visual checks sample single pixels with grim (-t ppm) inside solid-colour clients.
"""
from __future__ import annotations

import select
import subprocess
import time

from harness import GRIM, HERE, PYTHON, Client, E2EFailure, Nested, walk
from sway_apps import ipc

RED, GREEN, BLUE = (255, 0, 0), (0, 255, 0), (0, 0, 255)
ALT, CTRL, LOGO = 8, 4, 64
HYPER = ALT | CTRL | LOGO
PEEK = "lift_tiled_on_press enable"
MOD = "floating_modifier Mod1 normal"
WHEEL = ("bindsym --whole-window Mod4+Control+Mod1+button4 z raise\n"
         "bindsym --whole-window Mod4+Control+Mod1+button5 z lower")


def colored(s: Nested, app_id: str, color: str, size: str = "400x300", floating: bool = False,
            fullscreen: bool = False, visible: bool = True) -> Client:
    log = s.dir / f"{app_id}.log"
    argv = [PYTHON, str(HERE / "client.py"), "--app-id", app_id, "--size", size, "--log", str(log), "--color", color]
    if fullscreen:
        argv.append("--fullscreen")
    if floating:
        s.cmd(f'for_window [app_id="^{app_id}$"] floating enable')
    p = subprocess.Popen(argv, env=s.env, stdout=subprocess.DEVNULL, stderr=open(s.dir / f"{app_id}.err", "w"))
    c = Client(s, app_id, p, log)
    s.clients.append(c)
    s.wait(lambda: c.node() is not None and (c.node().get("visible", True) or not visible), f"{app_id} mapped", 10)
    return c


def place(c: Client, x: int, y: int) -> None:
    c.cmd(f"move position {x} {y}")
    c.nested.wait(lambda: (c.rect()["x"], c.rect()["y"]) == (x, y), f"{c.app_id} at {x},{y}")


def pixel(s: Nested, x: int, y: int) -> tuple[int, int, int]:
    out = subprocess.run([GRIM, "-g", f"{x},{y} 1x1", "-t", "ppm", "-"], env=s.env, check=True,
                         capture_output=True, timeout=10).stdout
    # "P6\n1 1\n255\n" + 3 bytes
    return tuple(out[-3:])


def near(a: tuple[int, int, int], b: tuple[int, int, int]) -> bool:
    return all(abs(p - q) <= 8 for p, q in zip(a, b))


def expect_pixel(s: Nested, x: int, y: int, color: tuple[int, int, int], what: str) -> None:
    s.wait(lambda: near(pixel(s, x, y), color), f"{what}: {color} at {x},{y} (last {pixel(s, x, y)})")


def hold_pixel(s: Nested, x: int, y: int, color: tuple[int, int, int], what: str, secs: float = 0.3) -> None:
    """Negative check: the colour must stay for `secs` (a few frames at 60 Hz)."""
    end = time.monotonic() + secs
    while time.monotonic() < end:
        got = pixel(s, x, y)
        if not near(got, color):
            raise E2EFailure(f"{what}: {got} at {x},{y}, expected {color}")
        time.sleep(0.03)


class Keys:
    def __init__(self, s: Nested) -> None:
        self.p = subprocess.Popen([PYTHON, str(HERE / "vkeyboard.py")], env=s.env, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True)
        s.children.append(self.p)
        if self.p.stdout.readline().strip() != "ready":
            raise E2EFailure("virtual keyboard did not start")

    def mods(self, mask: int) -> None:
        self.p.stdin.write(f"mods {mask}\n")
        self.p.stdin.flush()
        if self.p.stdout.readline().strip() != "ok":
            raise E2EFailure("virtual keyboard: mods failed")


def focused_ws(s: Nested) -> str:
    return next(w["name"] for w in s.workspaces() if w.get("focused"))


def floating_ids(s: Nested) -> list[int]:
    name = focused_ws(s)
    ws = next(n for n in walk(s.tree()) if n.get("type") == "workspace" and n.get("name") == name)
    return [n["id"] for n in ws["floating_nodes"]]


# ---- peek -------------------------------------------------------------------------------
def case_peek_lifts_covered_tile_while_held():
    with Nested(outputs=1, config=PEEK) as s:
        tile = colored(s, "e2e.tile", "ff0000")
        f = colored(s, "e2e.float", "0000ff", floating=True)
        place(f, 100, 100)
        expect_pixel(s, 300, 250, BLUE, "float over tile")
        for button in ("left", "right"):
            tile.clear_log()
            s.press(900, 500, button)
            expect_pixel(s, 300, 250, RED, f"tile lifted while {button} held")
            if tile.node()["type"] != "con" or f.node()["type"] != "floating_con":
                raise E2EFailure("peek changed the tree")
            s.release(button)
            expect_pixel(s, 300, 250, BLUE, f"tile back under the float after {button} release")
        # The lift is re-applied on every arrange: a transaction while held must keep it.
        s.press(900, 500)
        expect_pixel(s, 300, 250, RED, "lifted")
        s.cmd("gaps inner all set 4")
        expect_pixel(s, 300, 250, RED, "still lifted after a transaction")
        s.release()
        expect_pixel(s, 300, 250, BLUE, "released after the transaction")
        s.cmd("lift_tiled_on_press disable")
        s.press(900, 500)
        s.wait(lambda: "press 1" in tile.log_text(), "press reached the tile")
        hold_pixel(s, 300, 250, BLUE, "disabled: no peek")
        s.release()


def case_peek_not_on_middle_button_nor_floating_modifier():
    with Nested(outputs=1, config=f"{PEEK}\n{MOD}\ntiling_drag disable") as s:
        tile = colored(s, "e2e.tile", "ff0000")
        f = colored(s, "e2e.float", "0000ff", floating=True)
        place(f, 100, 100)
        expect_pixel(s, 300, 250, BLUE, "float over tile")
        s.press(900, 500, "middle")
        s.wait(lambda: "press 2" in tile.log_text(), "middle press reached the tile")
        hold_pixel(s, 300, 250, BLUE, "middle button: no peek")
        s.release("middle")
        keys = Keys(s)
        keys.mods(ALT)
        tile.clear_log()
        s.press(900, 500)
        s.wait(lambda: "press 1" in tile.log_text(), "Alt+press reached the tile (seatop_down)")
        hold_pixel(s, 300, 250, BLUE, "floating_modifier held: no peek")
        s.release()
        keys.mods(0)


def case_peek_off_with_fullscreen_view():
    with Nested(outputs=1, config=PEEK) as s:
        fs = colored(s, "e2e.fs", "ff0000", fullscreen=True)
        s.wait(lambda: fs.node()["fullscreen_mode"] == 1, "fullscreen")
        s.cmd('for_window [app_id="^e2e.float$"] above_fullscreen enable')
        f = colored(s, "e2e.float", "0000ff", floating=True, visible=False)
        if not f.node().get("above_fullscreen"):
            return  # sway without sway-above-fullscreen.patch: the float is hidden anyway
        place(f, 100, 100)
        expect_pixel(s, 300, 250, BLUE, "above_fullscreen float drawn")
        fs.clear_log()
        s.press(900, 500)
        s.wait(lambda: "press 1" in fs.log_text(), "press reached the fullscreen view")
        hold_pixel(s, 300, 250, BLUE, "fullscreen view is never lifted")
        s.release()


# ---- pin ----------------------------------------------------------------------------------
def case_pin_band_survives_clicks_and_sticky_switch():
    with Nested(outputs=1) as s:
        p = colored(s, "e2e.pin", "00ff00", "300x300", floating=True)
        place(p, 100, 100)
        n = colored(s, "e2e.norm", "0000ff", "300x300", floating=True)
        place(n, 250, 150)
        expect_pixel(s, 320, 250, BLUE, "newest float on top")
        p.cmd("pin enable")
        expect_pixel(s, 320, 250, GREEN, "pinned float raised over the band")
        if p.node().get("pinned") is not True:
            raise E2EFailure("get_tree does not report pinned")
        s.click(500, 400)
        s.wait(lambda: n.node()["focused"], "click focused the normal float")
        hold_pixel(s, 320, 250, GREEN, "focusing a normal float keeps it under the pinned one")
        n.cmd("focus")
        hold_pixel(s, 320, 250, GREEN, "focus command keeps the band")
        if floating_ids(s) != [n.con_id, p.con_id]:
            raise E2EFailure(f"floating order {floating_ids(s)}")

        # Sticky floaters are re-added on every workspace switch; they must land below
        # the pinned floaters already there.
        n.cmd("sticky enable")
        p.cmd("move to workspace 2")
        s.cmd("workspace 2")
        s.wait(lambda: n.node()["visible"] and p.node()["visible"], "both on workspace 2")
        expect_pixel(s, 320, 250, GREEN, "sticky float re-added under the pinned one")
        s.cmd("workspace 1")
        s.cmd("workspace 2")
        hold_pixel(s, 320, 250, GREEN, "after another switch")
        # sticky + pinned together
        p.cmd("sticky enable")
        s.cmd("workspace 3")
        s.wait(lambda: focused_ws(s) == "3", "on workspace 3")
        expect_pixel(s, 320, 250, GREEN, "sticky pinned float stays on top")
        p.cmd("pin disable")
        s.click(500, 400)
        expect_pixel(s, 320, 250, BLUE, "unpinned: a click raises the other float again")


def case_pin_refused_on_tiled():
    with Nested(outputs=1) as s:
        t = colored(s, "e2e.tile", "ff0000")
        for command in ("pin enable", "pin toggle", "z raise"):
            try:
                t.cmd(command)
            except ipc.IpcError as exc:
                if "floating" not in str(exc):
                    raise E2EFailure(f"{command}: unexpected error {exc}")
                continue
            raise E2EFailure(f"{command} accepted on a tiled window")
        t.cmd("pin disable")  # harmless
        if t.node().get("pinned"):
            raise E2EFailure("tiled window pinned")


# ---- z --------------------------------------------------------------------------------------
def case_z_raise_lower_within_band():
    with Nested(outputs=1, config=WHEEL) as s:
        a = colored(s, "e2e.a", "ff0000", "300x300", floating=True)
        b = colored(s, "e2e.b", "00ff00", "300x300", floating=True)
        c = colored(s, "e2e.c", "0000ff", "300x300", floating=True)
        for w in (a, b, c):
            place(w, 200, 200)
        ids = {a.con_id: "a", b.con_id: "b", c.con_id: "c"}

        def order() -> str:
            return "".join(ids[i] for i in floating_ids(s))

        expect_pixel(s, 350, 350, BLUE, "c on top")
        c.cmd("z lower")
        s.wait(lambda: order() == "acb", f"z lower once (order {order()})")
        expect_pixel(s, 350, 350, GREEN, "b on top after c lowered")
        c.cmd("z lower")
        c.cmd("z lower")
        s.wait(lambda: order() == "cab", f"bottom stays bottom (order {order()})")
        a.cmd("z raise")
        s.wait(lambda: order() == "cba", f"z raise (order {order()})")
        expect_pixel(s, 350, 350, RED, "a on top")

        keys = Keys(s)
        keys.mods(HYPER)
        s.scroll(350, 350, 1)                       # Hyper+button5 on the top float (a)
        s.wait(lambda: order() == "cab", f"wheel lowers the float under the cursor (order {order()})")
        expect_pixel(s, 350, 350, GREEN, "b on top after the wheel")
        s.scroll(350, 350, -1)                      # Hyper+button4 on b: already top
        time.sleep(0.1)
        if order() != "cab":
            raise E2EFailure(f"raise of the top float changed the order: {order()}")
        keys.mods(0)

        c.cmd("pin enable")
        s.wait(lambda: order() == "abc", f"pinned c is the tail (order {order()})")
        b.cmd("z raise")
        c.cmd("z lower")
        time.sleep(0.1)
        if order() != "abc":
            raise E2EFailure(f"z crossed the pin band: {order()}")
        expect_pixel(s, 350, 350, BLUE, "pinned c on top")


# ---- IPC ------------------------------------------------------------------------------------
def collect_moves(conn: ipc.Connection, con_id: int, timeout: float = 2.0) -> list[dict]:
    out, end = [], time.monotonic() + timeout
    while time.monotonic() < end:
        r, _, _ = select.select([conn.fileno()], [], [], max(0.0, end - time.monotonic()))
        if not r:
            break
        kind, body = conn.next_event()
        if kind == "window" and body.get("change") == "move" and body["container"]["id"] == con_id:
            out.append(body["container"])
            end = min(end, time.monotonic() + 0.2)
    return out


def case_floating_drag_and_resize_emit_window_move():
    with Nested(outputs=1, config=MOD) as s:
        f = colored(s, "e2e.float", "0000ff", "300x200", floating=True)
        place(f, 100, 100)
        events = ipc.Connection(s.env["SWAYSOCK"])
        try:
            events.subscribe(["window"])
            keys = Keys(s)
            keys.mods(ALT)
            s.press(200, 200)
            s.pointer_to(300, 250)
            s.release()
            keys.mods(0)
            moves = collect_moves(events, f.con_id)
            if not moves or (moves[-1]["rect"]["x"], moves[-1]["rect"]["y"]) != (200, 150):
                raise E2EFailure(f"Alt-drag: window:move events {[m['rect'] for m in moves]}")
            keys.mods(ALT)
            s.press(400, 300, "right")
            s.pointer_to(450, 330)
            s.release("right")
            keys.mods(0)
            moves = collect_moves(events, f.con_id)
            if not moves:
                raise E2EFailure("Alt-right resize emitted no window:move")
            f.cmd("resize set 350 250")
            moves = collect_moves(events, f.con_id)
            if not moves or (moves[-1]["rect"]["width"], moves[-1]["rect"]["height"]) != (350, 250):
                raise E2EFailure(f"resize command: {[m['rect'] for m in moves]}")
        finally:
            events.close()
