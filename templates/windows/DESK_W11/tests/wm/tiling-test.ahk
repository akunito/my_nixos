#Requires AutoHotkey v2.0
#SingleInstance Force
; Tiling, the sway way: windows share the workspace, the gaps are sway's, the
; split follows the monitor shape, and focus/move/resize/float behave like the
; sway keymap. Needs config.yaml with `initial_state: tiling`.
; Run: AutoHotkey64.exe tiling-test.ahk   -> %TEMP%\perf\tiling-test.txt
#Include ..\..\lib-window-state.ahk
#Include ..\..\lib-glaze.ahk
#Include ..\..\lib-app-toggle.ahk

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
CheckNear(name, got, want, tol) {
    global out, fails
    ok := Abs(got - want) <= tol
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want " +-" tol ")`n"
    if !ok
        fails++
}
Note(msg) {
    global out
    out .= "     " msg "`n"
}
R(hwnd) {
    b := Buffer(16, 0)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", b)
    return Map("l", NumGet(b, 0, "Int"), "t", NumGet(b, 4, "Int"),
               "r", NumGet(b, 8, "Int"), "b", NumGet(b, 12, "Int"),
               "w", NumGet(b, 8, "Int") - NumGet(b, 0, "Int"),
               "h", NumGet(b, 12, "Int") - NumGet(b, 4, "Int"))
}
Rs(hwnd) {
    r := R(hwnd)
    return r["l"] "," r["t"] " " r["w"] "x" r["h"]
}
WinRec(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w
    return Map("id", "", "ws", "unmanaged", "state", "-", "display", "-", "sticky", false)
}
Overlap(a, b) {
    ra := R(a), rb := R(b)
    return (ra["l"] < rb["r"] && rb["l"] < ra["r"] && ra["t"] < rb["b"] && rb["t"] < ra["b"]) ? 1 : 0
}
StartTiled(&pid) {
    global flip
    Run(flip " 300 0 tiled", , , &pid)
    WinWait("ahk_pid " pid, , 10)
    Sleep 1500
    return WinExist("ahk_pid " pid)
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

KillFlips()
startWs := GlazeFocusedWs()
home := EmptyWs("1")
Glaze("focus --workspace " home)
Sleep 1200
DllCall("SetCursorPos", "Int", 30, "Int", 1000)     ; parked: no pointer focus changes
Note("home " home ", started on " startWs)

; --- two windows share the workspace --------------------------------------
a := StartTiled(&pa)
b := StartTiled(&pb)
Check("1 both are tiling", WinRec(a)["state"] "/" WinRec(b)["state"], "tiling/tiling")
ra := R(a), rb := R(b)
Note("1 rects " Rs(a) " | " Rs(b))
Check("1 they do not overlap", Overlap(a, b), 0)
Check("1 same height", ra["h"] = rb["h"] ? 1 : 0, 1)
CheckNear("1 equal widths", ra["w"], rb["w"], 2)
left := ra["l"] < rb["l"] ? ra : rb, right := ra["l"] < rb["l"] ? rb : ra
gap := right["l"] - left["r"]
Note("1 gap between them: " gap " px (sway 8 px, scaled by the 150% DPI -> 12)")
Check("1 sway's inner gap", (gap >= 8 && gap <= 20) ? 1 : 0, 1)
span := right["r"] - left["l"]
mw := A_ScreenWidth
Check("1 they fill the monitor", (span > mw * 0.9) ? 1 : 0, 1)

; --- a third one splits again ---------------------------------------------
c := StartTiled(&pc)
rc := R(c)
Note("2 rects " Rs(a) " | " Rs(b) " | " Rs(c))
CheckNear("2 three equal columns", R(a)["w"], rc["w"], 3)
Check("2 none of them overlap", Overlap(a, c) + Overlap(b, c), 0)

; --- closing one re-flows the rest -----------------------------------------
ProcessClose(pc)
Sleep 1500
Note("3 rects " Rs(a) " | " Rs(b))
la := R(a), lb := R(b)
Check("3 the two left fill the monitor again",
    ((Max(la["r"], lb["r"]) - Min(la["l"], lb["l"])) > mw * 0.9) ? 1 : 0, 1)

; --- focus and move by direction -------------------------------------------
leftHwnd := R(a)["l"] < R(b)["l"] ? a : b
rightHwnd := leftHwnd = a ? b : a
Glaze("focus --container-id " WinRec(leftHwnd)["id"])
Sleep 800
Glaze("focus --direction right")
Sleep 800
Check("4 focus moves to the right neighbour", WinRec(rightHwnd)["focus"] ? 1 : 0, 1)
Glaze("focus --direction left")
Sleep 800
Check("4 and back to the left one", WinRec(leftHwnd)["focus"] ? 1 : 0, 1)

beforeLeft := R(leftHwnd)["l"]
Glaze("move --direction right")
Sleep 1200
Note("5 rects " Rs(leftHwnd) " | " Rs(rightHwnd))
Check("5 the window swapped sides", R(leftHwnd)["l"] > beforeLeft ? 1 : 0, 1)

; --- resize ----------------------------------------------------------------
wBefore := R(leftHwnd)["w"]
Glaze("resize --width 10%")
Sleep 1200
Note("6 width " wBefore " -> " R(leftHwnd)["w"])
Check("6 the focused window grew", R(leftHwnd)["w"] > wBefore ? 1 : 0, 1)

; --- floating takes it out of the layout -----------------------------------
Glaze("toggle-floating --centered=false")
Sleep 1200
Check("7 it is floating now", WinRec(leftHwnd)["state"], "floating")
Check("7 the other one fills the workspace", (R(rightHwnd)["w"] > mw * 0.9) ? 1 : 0, 1)
Glaze("toggle-floating")
Sleep 1000
Check("7 and tiling again", WinRec(leftHwnd)["state"], "tiling")

; --- the vertical monitor stacks instead of splitting ----------------------
KillFlips()
vert := EmptyWs("2")
Glaze("focus --workspace " vert)
Sleep 1200
d := StartTiled(&pd)
e := StartTiled(&pe)
rd := R(d), re := R(e)
Note("8 rects " Rs(d) " | " Rs(e))
Check("8 both tiling on the vertical monitor", WinRec(d)["state"] "/" WinRec(e)["state"], "tiling/tiling")
Check("8 stacked, not side by side", (rd["w"] = re["w"] && rd["t"] != re["t"]) ? 1 : 0, 1)

KillFlips()
if (startWs != "")
    Glaze("focus --workspace " startWs)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\tiling-test.txt")
FileAppend(out, A_Temp "\perf\tiling-test.txt")
ExitApp
