; Workspace keys, Sway's way (AutoHotkey v2). Needs lib-glaze.ahk.
;
; In Sway the focused output is the one under the POINTER: move the mouse to
; the other monitor and Hyper+1..9 / Hyper+Q/W act there, even over an empty
; desktop. Windows never moves the focus onto a bare desktop, so taking the
; monitor from the focused window made the keys act on the monitor you were
; not looking at -- "Hyper+Q/W does nothing" (measured 2026-09-20: the chord
; switched the vertical monitor while the pointer was on the main one).
;
; Workspace names carry their monitor: 1x on the main monitor, 2x on the
; vertical one (Sway's swaysome groups).
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\lib-glaze.ahk

PrimaryMon() => DllCall("MonitorFromPoint", "Int64", 0, "UInt", 1, "Ptr")

; The monitor under the pointer = Sway's focused output.
CursorGroup() {
    MouseGetPos &mx, &my
    mon := DllCall("MonitorFromPoint", "Int64", (my << 32) | (mx & 0xFFFFFFFF), "UInt", 2, "Ptr")
    return mon = PrimaryMon() ? 1 : 2
}

; The monitor of a window, for the commands that act on a window instead of on
; a place: moving a window to "workspace 3" means its own monitor's third
; workspace, not the one the pointer happens to rest on.
WindowGroup(hwnd := 0) {
    if !hwnd
        hwnd := WinExist("A")
    if (!hwnd || WinGetClass("ahk_id " hwnd) = "Progman" || WinGetClass("ahk_id " hwnd) = "WorkerW")
        return CursorGroup()
    return DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr") = PrimaryMon() ? 1 : 2
}

FocusGroup() => CursorGroup()             ; kept: the old name, the new rule
Ws(n) => CursorGroup() * 10 + Mod(n, 10)  ; Hyper+1..9 -> x1..x9, Hyper+0 -> x0
MoveWs(n) => WindowGroup() * 10 + Mod(n, 10)

; The workspace displayed on a monitor group, from a snapshot when there is one
; (every query costs ~200 ms, and a gesture should take one at most).
CurrentWs(group, wss := 0) {
    if !wss
        wss := GlazeWss()
    for name, shown in wss
        if (shown && SubStr(name, 1, 1) = group)
            return name
    return group "1"
}

WsCycle(delta, move := false) {
    g := move ? WindowGroup() : CursorGroup()
    cur := CurrentWs(g), i := 1
    order := [g "1", g "2", g "3", g "4", g "5", g "6", g "7", g "8", g "9", g "0"]
    for k, v in order
        if (v = cur)
            i := k
    n := order[Mod(i - 1 + delta + 10, 10) + 1]
    if move
        Glaze("move --workspace " n)
    Glaze("focus --workspace " n)
}
