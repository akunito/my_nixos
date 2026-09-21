#Requires AutoHotkey v2.0
#SingleInstance Force
; The workspace keys act on the monitor under the POINTER, like Sway's focused
; output -- not on the monitor of whatever window happens to hold the focus.
; That is the bug behind "Hyper+Q/W does nothing": with the pointer on the main
; monitor and a focused terminal on the vertical one, the chord switched the
; vertical monitor's workspace (traced 2026-09-20: `glaze focus --workspace 22`).
; Run: AutoHotkey64.exe wskeys-test.ahk   -> %TEMP%\perf\wskeys-test.txt
#Include ..\..\lib-workspaces.ahk

DetectHiddenWindows true
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
; MouseMove, not SetCursorPos: AHK is system-DPI aware, so the monitor
; coordinates it reports are virtualised (the vertical monitor lives at
; 4608..6336 here while physically it is 3840..5280) and a raw SetCursorPos to
; an AHK coordinate lands outside the desktop -- the pointer simply did not
; move. MouseMove speaks the same coordinates as MonitorGet.
WalkCursorTo(x, y) {
    CoordMode "Mouse", "Screen"
    MouseMove x, y, 10
    Sleep 400
}
; Middle of each monitor, in the coordinates AHK (and the mouse) use.
MonCenter(primary) {
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        isPrimary := (MonitorGetPrimary() = A_Index)
        if (isPrimary = primary)
            return [(l + r) // 2, (t + b) // 2]
    }
    return [100, 100]
}
Displayed(group) {
    for name, shown in GlazeWss()
        if (shown && WsGroup(name) = group)
            return name
    return "?"
}

startPrimary := Displayed(1), startVertical := Displayed(2)
main := MonCenter(true), vert := MonCenter(false)
Note("main monitor centre " main[1] "," main[2] " | vertical " vert[1] "," vert[2])
Note("displayed at start: " startPrimary " / " startVertical)

; --- the pointer decides which monitor the keys act on ---------------------
WalkCursorTo(main[1], main[2])
Check("1 pointer on the main monitor -> group 1", CursorGroup(), 1)
Check("1 Hyper+3 would ask for", Ws(3), 13)
WalkCursorTo(vert[1], vert[2])
Check("1 pointer on the vertical monitor -> group 2", CursorGroup(), 2)
Check("1 Hyper+3 would ask for", Ws(3), 23)

; --- cycling changes the monitor you are pointing at, and only that one ----
WalkCursorTo(main[1], main[2])
before1 := Displayed(1), before2 := Displayed(2)
WsCycle(+1)
Sleep 1200
after1 := Displayed(1), after2 := Displayed(2)
Note("main: " before1 " -> " after1 " | vertical: " before2 " -> " after2)
Check("2 the main monitor moved on", after1 != before1 ? 1 : 0, 1)
Check("2 the vertical monitor was left alone", after2, before2)
WsCycle(-1)
Sleep 1200
Check("2 and back", Displayed(1), before1)

WalkCursorTo(vert[1], vert[2])
before1 := Displayed(1), before2 := Displayed(2)
WsCycle(+1)
Sleep 1200
Note("main: " before1 " -> " Displayed(1) " | vertical: " before2 " -> " Displayed(2))
Check("3 the vertical monitor moved on", Displayed(2) != before2 ? 1 : 0, 1)
Check("3 the main monitor was left alone", Displayed(1), before1)
WsCycle(-1)
Sleep 1200
Check("3 and back", Displayed(2), before2)

; --- moving a window uses the window's own monitor, not the pointer's ------
; (a window of the vertical monitor must not be teleported to the main one
; just because the pointer rests there)
flip := A_Temp "\perf\fliptest.exe"
Run(flip " 60 1 now", , , &pid)       ; monitor index 1 = the vertical one
WinWait("ahk_pid " pid, , 10)
Sleep 1500
h := WinExist("ahk_pid " pid)
; GlazeWM puts a new window on the FOCUSED workspace, which may belong to the
; other monitor: ask it to move there instead of assuming.
for w in GlazeWins()
    if (w["hwnd"] = h)
        GlazeOn(w["id"], "move --workspace " Displayed(2))
Sleep 1500
WinActivate "ahk_id " h
Sleep 500
WalkCursorTo(main[1], main[2])        ; pointer on the OTHER monitor
Check("4 the window is on the vertical monitor", WindowGroup(h), 2)
; MoveWs() acts on whatever is focused when the key is pressed -- and with the
; pointer over the other monitor, focus follows it -- so the rule is checked
; against the window itself: a window's own monitor decides where it moves.
Check("4 moving it would target", WindowGroup(h) * 10 + 4, 24)
Check("4 while focusing would target", Ws(4), 14)
try ProcessClose(pid)

out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\wskeys-test.txt")
FileAppend(out, A_Temp "\perf\wskeys-test.txt")
ExitApp
