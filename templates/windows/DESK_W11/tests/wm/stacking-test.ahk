#Requires AutoHotkey v2.0
#SingleInstance Force
; Floating windows stay above the tiled ones, the way sway stacks a workspace
; (tiling layer < floating layer < fullscreen). A floating terminal or Telegram
; must never end up buried under a tiled window -- but must still go UNDER a
; fullscreen game sharing the workspace, or the game loses its direct path to
; the screen.
; Run: AutoHotkey64.exe stacking-test.ahk   -> %TEMP%\perf\stacking-test.txt
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
Note(msg) {
    global out
    out .= "     " msg "`n"
}
Above(a, b) {                       ; is a above b in the z-order?
    h := DllCall("GetTopWindow", "Ptr", 0, "Ptr")
    while h {
        if (h = a)
            return true
        if (h = b)
            return false
        h := DllCall("GetWindow", "Ptr", h, "UInt", 2, "Ptr")
    }
    return false
}
Rec(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w
    return Map("id", "", "state", "unmanaged", "ws", "?", "sticky", false)
}
Topmost(hwnd) => (DllCall("GetWindowLong", "Ptr", hwnd, "Int", -20) & 0x8) ? 1 : 0   ; WS_EX_TOPMOST
StartFlip(args, &pid) {
    global flip
    Run(flip " " args, , , &pid)
    WinWait("ahk_pid " pid, , 10)
    Sleep 1800
    return WinExist("ahk_pid " pid)
}
KillFlips() {
    try RunWait(A_ComSpec ' /c taskkill /F /IM fliptest.exe', , "Hide")
    Sleep 1200
}
EmptyWs(prefix, skip := "") {
    used := Map()
    for w in GlazeWins()
        used[w["ws"]] := true
    Loop 9 {
        n := prefix A_Index
        if (n != skip && !used.Has(n))
            return n
    }
    return prefix "9"
}
FocusWs(ws) {
    wss := GlazeWss()
    if (!wss.Has(ws) || !wss[ws]) {
        Glaze("focus --workspace " ws)
        Sleep 1200
    }
}

KillFlips()
startWs := GlazeFocusedWs()
home := EmptyWs("1")
FocusWs(home)
other := EmptyWs("1", home)
Note("home " home ", spare " other ", started on " startWs)

; --- 1. the floating one is above the tiled one ---------------------------
tiled := StartFlip("300 0 tiled", &pt)
floatWin := StartFlip("300 0 500 400 1100 800 now", &pf)
Check("1 setup: one tiled, one floating", Rec(tiled)["state"] "/" Rec(floatWin)["state"], "tiling/floating")
Check("1 the floating one is kept on top", Topmost(floatWin), 1)
Check("1 the tiled one is not", Topmost(tiled), 0)
Check("1 and it really is above", Above(floatWin, tiled) ? 1 : 0, 1)

; Focusing the tiled window must not bury the floating one (sway: the layers
; do not swap, only the order inside a layer does).
Glaze("focus --container-id " Rec(tiled)["id"])
Sleep 1000
Check("2 still above after focusing the tiled window", Above(floatWin, tiled) ? 1 : 0, 1)

; --- 3. a workspace round trip keeps the stacking -------------------------
GlazeOn(Rec(floatWin)["id"], "set-sticky")
Sleep 900
FocusWs(other)
Sleep 1200
FocusWs(home)
Sleep 1500
Note("3 sticky=" (Rec(floatWin)["sticky"] ? 1 : 0) " ws=" Rec(floatWin)["ws"] " topmost=" Topmost(floatWin))
Check("3 still above after coming back", Above(floatWin, tiled) ? 1 : 0, 1)

; --- 4. a game going fullscreen pushes it under -------------------------
game := StartFlip("90 0 gamelike", &pg)
Sleep 2500
Check("4 setup: the game is fullscreen", Rec(game)["state"], "fullscreen")
Check("4 setup: same workspace", Rec(game)["ws"], Rec(floatWin)["ws"])
Note("4 floatWin topmost=" Topmost(floatWin) " above-game=" (Above(floatWin, game) ? 1 : 0))
Check("4 the always-on-top window goes under the game", Above(floatWin, game) ? 1 : 0, 0)
try ProcessClose(pg)
Sleep 2000

; --- 5. floating -> tiling drops the always-on-top ------------------------
GlazeOn(Rec(floatWin)["id"], "unset-sticky")
Sleep 700
GlazeOn(Rec(floatWin)["id"], "set-tiling")
Sleep 1500
Note("5 state=" Rec(floatWin)["state"] " topmost=" Topmost(floatWin))
Check("5 it tiles now", Rec(floatWin)["state"], "tiling")
Check("5 and lost the always-on-top", Topmost(floatWin), 0)

KillFlips()
if (startWs != "")
    Glaze("focus --workspace " startWs)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\stacking-test.txt")
FileAppend(out, A_Temp "\perf\stacking-test.txt")
ExitApp
