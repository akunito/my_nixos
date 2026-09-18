#Requires AutoHotkey v2.0
#SingleInstance Force
; Checks the helpers that decide whether Hyper+<letter> may minimise a window.
; Run: AutoHotkey64.exe window-state-test.ahk   -> %TEMP%\perf\window-state-test.txt
#Include ..\..\lib-window-state.ahk
DetectHiddenWindows true
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
Run(A_Temp "\perf\fliptest.exe 25 0", , , &pid)
WinWait("ahk_class FlipTestWnd", , 10)
h := WinExist("ahk_class FlipTestWnd")
Sleep 1500
Check("a visible window is on screen", IsOnScreen(h) ? 1 : 0, 1)
Check("not cloaked", Cloaked(h), 0)
RunWait(A_Temp '\perf\cloaktest.exe ' h ' 1', , "Hide")      ; cloak it like GlazeWM does
Sleep 600
Check("shell-cloaked window is off screen", IsOnScreen(h) ? 1 : 0, 0)
Check("cloak flag is the shell one", Cloaked(h), 2)
RunWait(A_Temp '\perf\cloaktest.exe ' h ' 0', , "Hide")
Sleep 600
Check("uncloaked again", IsOnScreen(h) ? 1 : 0, 1)
WinMinimize("ahk_id " h)
Sleep 600
Check("minimised window is off screen", IsOnScreen(h) ? 1 : 0, 0)
WinRestore("ahk_id " h)
Sleep 600
WinHide("ahk_id " h)
Sleep 400
Check("hidden window is off screen", IsOnScreen(h) ? 1 : 0, 0)
ProcessClose(pid)
out .= (fails ? fails " failed" : "all passed") "`n"
try FileDelete(A_Temp "\perf\window-state-test.txt")
FileAppend(out, A_Temp "\perf\window-state-test.txt")
ExitApp
