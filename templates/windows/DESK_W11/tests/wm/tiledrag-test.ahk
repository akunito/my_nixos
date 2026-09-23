#Requires AutoHotkey v2.0
#SingleInstance Force
; Alt+drag on a TILED window must keep it tiled: it swaps places or resizes the
; layout, like the same gesture in sway. Before this, the drag repositioned the
; real window, GlazeWM read that as "the user pulled it out of the layout" and
; turned it floating, losing its place and its size.
;
; The gesture itself cannot be faked from a script -- the drag loop watches the
; PHYSICAL button (`GetKeyState(..., "P")`), and injected clicks do not set it
; reliably -- so the three parts are checked separately: the gate that keeps a
; tiled window away from the free-form path, the decision the drop makes, and
; the effect of that decision on the layout. (What floated the window was not
; the repositioning by itself -- a plain WinMove leaves it tiling, checked --
; but moving it while the mouse button is down, which GlazeWM reads as the
; user pulling it out of the layout. That is exactly what the free-form drag
; did on every pixel.)
; Run: AutoHotkey64.exe tiledrag-test.ahk   -> %TEMP%\perf\tiledrag-test.txt
#Include ..\..\lib-app-toggle.ahk
#Include ..\..\lib-tiling-drag.ahk

DetectHiddenWindows true
flip := A_Temp "\perf\fliptest.exe"
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
Note(msg) {
    global out
    out .= "     " msg "`n"
}
WRect(hwnd) {
    b := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", b, "UInt", 16) != 0
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", b)
    return Map("l", NumGet(b, 0, "Int"), "t", NumGet(b, 4, "Int"),
               "w", NumGet(b, 8, "Int") - NumGet(b, 0, "Int"),
               "h", NumGet(b, 12, "Int") - NumGet(b, 4, "Int"))
}
Rec(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w
    return Map("id", "", "state", "unmanaged", "ws", "?",
               "focus", false, "display", "-", "sticky", false, "proc", "-", "class", "-", "hwnd", 0, "title", "-")
}
StartFlip(args, &pid) {
    global flip
    Run(flip " " args, , , &pid)
    WinWait("ahk_pid " pid, , 10)
    Sleep 1500
    return WinExist("ahk_pid " pid)
}
; The pointer decides the focus, the focused workspace decides the monitor a
; new window is born on: park it on the main monitor before creating any.
ParkOnMain() {
    CoordMode "Mouse", "Screen"
    Loop MonitorGetCount() {
        if (A_Index = MonitorGetPrimary()) {
            MonitorGet(A_Index, &l, &t, &r, &b)
            MouseMove((l + r) // 2, (t + b) // 2, 10)
            Sleep 500
            return
        }
    }
}
KillFlips() {
    try RunWait(A_ComSpec ' /c taskkill /F /IM fliptest.exe', , "Hide")
    Sleep 1200
}
EmptyWs(prefix) {
    used := Map()
    for w in GlazeWins()
        used[w["ws"]] := true
    Loop 9 {
        n := prefix A_Index
        if (!used.Has(n))
            return n
    }
    return prefix "9"
}

; --- 1. what a drop means, as a plain function ----------------------------
Check("1 the right edge pulled right widens", TilingDropCommand("resize", 240, 0, false, false), "resize --width 240px")
Check("1 the left edge pulled left widens", TilingDropCommand("resize", -240, 0, true, false), "resize --width 240px")
Check("1 the top edge pulled up heightens", TilingDropCommand("resize", 0, -180, false, true), "resize --height 180px")
Check("1 both edges at once", TilingDropCommand("resize", 100, 120, false, false), "resize --width 100px --height 120px")
Check("1 a twitch means nothing", TilingDropCommand("resize", 4, -6, false, false), "")

; --- 2. the gate: only a tiled window takes the tiling path ---------------
KillFlips()
startWs := GlazeFocusedWs()
home := EmptyWs("1")
wss := GlazeWss()
if (!wss.Has(home) || !wss[home]) {
    Glaze("focus --workspace " home)
    Sleep 1200
}
ParkOnMain()
Note("home " home ", started on " startWs)
a := StartFlip("300 0 tiled", &pa)
b := StartFlip("300 0 tiled", &pb)
Check("2 setup: two tiled windows", Rec(a)["state"] "/" Rec(b)["state"], "tiling/tiling")
Check("2 a tiled window has a tiling id", GlazeTilingIdOf(a) != "" ? 1 : 0, 1)
GlazeOn(Rec(a)["id"], "set-floating --centered=false")
Sleep 1200
Check("2 a floating one has none (the free-form drag keeps it)", GlazeTilingIdOf(a), "")
GlazeOn(Rec(a)["id"], "set-tiling")
Sleep 1200
Check("2 tiled again", Rec(a)["state"], "tiling")

; --- 3. the effect: the drop keeps both windows tiled ---------------------
; A move is no longer a direction: the drop reports the POINT the pointer is
; on and the window manager reads it as a place in the layout (2026-09-21).
; What is checked here is the outline -- it has to be the rectangle the drop
; will produce, or the shadow is lying about where the window lands, which is
; the whole complaint this replaced.
ra1 := WRect(a), rb1 := WRect(b)
leftOutline := ra1["l"] < rb1["l"] ? a : b
rightOutline := leftOutline = a ? b : a
rr := WRect(rightOutline)
; The outline is the rectangle the DROP will produce, not half of the tile
; under the pointer (the window manager makes the drop on a copy of the tree
; and reads the landing back; a drop beside a tile whose row already splits
; that way joins the row as a sibling). With two tiles in a row: the left
; half of the right tile puts the dragged window before it -- where it
; already is -- and the right half puts it after, in the right column.
rl := WRect(leftOutline)
Check("3 the outline for the left half of the other tile is the left column",
    TilingDropTarget(Rec(leftOutline)["id"], rr["l"] + rr["w"] // 4, rr["t"] + rr["h"] // 2),
    rl["l"] "," rl["t"] "," rl["w"] "," rl["h"])
Check("3 and for the right half, the right column",
    TilingDropTarget(Rec(leftOutline)["id"], rr["l"] + (rr["w"] * 3) // 4, rr["t"] + rr["h"] // 2),
    rr["l"] "," rr["t"] "," rr["w"] "," rr["h"])
Check("3 the window's own tile is not a target",
    TilingDropTarget(Rec(leftOutline)["id"], WRect(leftOutline)["l"] + 40, WRect(leftOutline)["t"] + 40) = "" ? 1 : 0, 1)
ra := WRect(a), rb := WRect(b)
leftHwnd := ra["l"] < rb["l"] ? a : b
rightHwnd := leftHwnd = a ? b : a
beforeLeft := WRect(leftHwnd)["l"]
; Dropped on the RIGHT half of the other tile: with two windows that is a
; swap, and it is the point under the pointer that says so, not the direction
; the hand travelled.
rr3 := WRect(rightHwnd)
GlazeOn(Rec(leftHwnd)["id"],
    "drag-tile --x " (rr3["l"] + (rr3["w"] * 3) // 4) " --y " (rr3["t"] + rr3["h"] // 2))
Sleep 1500
Note("3 left window " beforeLeft " -> " WRect(leftHwnd)["l"])
Check("3 the dropped window swapped places", WRect(leftHwnd)["l"] > beforeLeft ? 1 : 0, 1)
Check("3 and is still tiling", Rec(leftHwnd)["state"], "tiling")
Check("3 so is the other one", Rec(rightHwnd)["state"], "tiling")

; Re-read the layout: the drop above moved a window, and the resize has to
; act on the one that still HAS a neighbour to its right -- `move --direction
; right` on the rightmost window sends it to the next monitor, where a lone
; tiled window fills the workspace and cannot be resized at all.
Sleep 1000
r1 := WRect(a), r2 := WRect(b)
sameMonitor := Abs(r1["l"] - r2["l"]) < 3840 && r1["t"] = r2["t"]
resizeMe := r1["l"] < r2["l"] ? a : b
Note("4 resizing the left one of " r1["l"] " / " r2["l"] (sameMonitor ? "" : " (they are not side by side any more)"))
wBefore := WRect(resizeMe)["w"]
GlazeOn(Rec(resizeMe)["id"], TilingDropCommand("resize", 300, 0, false, false))
Sleep 1500
wAfter := WRect(resizeMe)["w"]
Note("4 width " wBefore " -> " wAfter)
; GlazeWM moves the split edge, and for the window at the edge of the row that
; means the neighbour takes the pixels: what matters is that the drop resized
; the layout by the distance dragged, and that nothing left the layout.
Check("4 the resize drop moved the split by the drag",
    Abs(Abs(wAfter - wBefore) - 300) < 120 ? 1 : 0, 1)
Check("4 still tiling", Rec(resizeMe)["state"], "tiling")
Check("4 the other one too", Rec(resizeMe = a ? b : a)["state"], "tiling")

KillFlips()
if (startWs != "")
    Glaze("focus --workspace " startWs)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\tiledrag-test.txt")
FileAppend(out, A_Temp "\perf\tiledrag-test.txt")
ExitApp
