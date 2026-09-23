#Requires AutoHotkey v2.0
#SingleInstance Force
; Sticky windows: shown on every workspace of their monitor (sway's `sticky
; enable`). Needs the fork build with set-sticky / unset-sticky / toggle-sticky.
; Run: AutoHotkey64.exe sticky-test.ahk   -> %TEMP%\perf\sticky-test.txt
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
Note(msg) {
    global out
    out .= "     " msg "`n"
}
WinRec(hwnd) {
    for w in GlazeWins()
        if (w["hwnd"] = hwnd)
            return w
    return Map("id", "", "ws", "unmanaged", "state", "-", "display", "-", "sticky", false,
               "focus", false, "proc", "-", "class", "-", "hwnd", 0, "title", "-")
}
RectOf(hwnd) {
    r := Buffer(16, 0)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", r)
    return NumGet(r, 0, "Int") "," NumGet(r, 4, "Int") " " (NumGet(r, 8, "Int") - NumGet(r, 0, "Int")) "x" (NumGet(r, 12, "Int") - NumGet(r, 4, "Int"))
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
    return prefix (skip = prefix "8" ? "9" : "8")
}

; Focus a workspace only when it is not already the one on its monitor:
; asking for the workspace you are on goes back to the previous one
; (workspace_auto_back_and_forth, on in the config), and this test asked for
; its home workspace right after computing it and again after a trip to the
; other monitor -- the window was born on the PREVIOUS workspace both times
; ("managed on the home workspace (got 15, want 12)", 2026-09-23).
FocusWs(ws) {
    for m in GlazeMonitors()
        for w in m["wss"]
            if (w["name"] = ws && w["displayed"])
                return
    Glaze("focus --workspace " ws)
}
KillFlips()
startWs := GlazeFocusedWs()
home := EmptyWs("1")
FocusWs(home)
Sleep 1200
other := EmptyWs("1", home)
Note("home " home ", spare " other ", started on " startWs)

Run(flip " 300 0 400 400 1000 800 now", , , &pid)
WinWait("ahk_pid " pid, , 10)
Sleep 1500
h := WinExist("ahk_pid " pid)
rec := WinRec(h)
Check("0 setup: managed on the home workspace", rec["ws"], home)
GlazeOn(rec["id"], "set-floating --centered=false")
Sleep 700
GlazeOn(rec["id"], "set-sticky")
Sleep 900
rec := WinRec(h)
Check("1 the flag is set and visible in the query", rec["sticky"] ? 1 : 0, 1)
before := RectOf(h)

; --- follows you to another workspace of the same monitor ------------------
FocusWs(other)
Sleep 1500
rec := WinRec(h)
Note("after the switch: ws=" rec["ws"] " display=" rec["display"] " cloaked=" Cloaked(h) " rect=" RectOf(h))
Check("2 still on screen on the next workspace", IsOnScreen(h) ? 1 : 0, 1)
Check("2 carried to the displayed workspace", rec["ws"], other)
Check("2 same size and place", RectOf(h), before)

FocusWs(home)
Sleep 1500
Check("3 and back again", IsOnScreen(h) ? 1 : 0, 1)
Check("3 on the workspace we returned to", WinRec(h)["ws"], home)

; --- the other monitor must not drag it away ------------------------------
vert := EmptyWs("2")
FocusWs(vert)
Sleep 1500
rec := WinRec(h)
Note("after focusing " vert ": ws=" rec["ws"] " cloaked=" Cloaked(h))
Check("4 stays on its own monitor", rec["ws"], home)
FocusWs(home)
Sleep 1200

; --- a fullscreen window keeps the screen to itself -----------------------
Run(flip " 60 0 gamelike", , , &gpid)
WinWait("ahk_pid " gpid, , 10)
Sleep 2500
game := WinExist("ahk_pid " gpid)
Check("5 setup: the game is fullscreen", WinRec(game)["state"], "fullscreen")
Check("5 setup: the game has the focus", WinActive("ahk_id " game) ? 1 : 0, 1)
Check("5 the sticky window stays under it", Above(h, game) ? 1 : 0, 0)
try ProcessClose(gpid)
Sleep 1500

; --- unsticky puts it back to normal --------------------------------------
GlazeOn(WinRec(h)["id"], "unset-sticky")
Sleep 700
Check("6 the flag is cleared", WinRec(h)["sticky"] ? 1 : 0, 0)
FocusWs(other)
Sleep 1500
rec := WinRec(h)
Note("after unsticky: ws=" rec["ws"] " display=" rec["display"] " cloaked=" Cloaked(h))
Check("6 hidden with its workspace again", IsOnScreen(h) ? 1 : 0, 0)
Check("6 left where it was", rec["ws"], home)

; --- toggle-sticky flips it -----------------------------------------------
GlazeOn(rec["id"], "toggle-sticky")
Sleep 900
Check("7 toggle-sticky sets it", WinRec(h)["sticky"] ? 1 : 0, 1)
GlazeOn(rec["id"], "toggle-sticky")
Sleep 700
Check("7 toggle-sticky clears it", WinRec(h)["sticky"] ? 1 : 0, 0)

KillFlips()
if (startWs != "")
    FocusWs(startWs)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\sticky-test.txt")
FileAppend(out, A_Temp "\perf\sticky-test.txt")
ExitApp
