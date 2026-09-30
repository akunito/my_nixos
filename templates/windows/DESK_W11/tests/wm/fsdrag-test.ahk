#Requires AutoHotkey v2.0
#SingleInstance Force
; Alt+drag leaves a fullscreen window alone (Alt is the game's own pointer key;
; dragging Aion 2 pulled it out of fullscreen, 2026-09-30) and still moves an
; ordinary window. The fullscreen window here is a borderless one the size of
; its monitor, which is the rectangle test; the journal test needs the daemon
; to have seen a real fullscreen window and is covered by the game itself.
; Run: AutoHotkey64.exe fsdrag-test.ahk -> %TEMP%\perf\fsdrag-test.txt
SendLevel 1
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
DetectHiddenWindows true
Check("0 setup: the hotkey script is there", WinExist("AkuWM hotkeys ahk_class AutoHotkeyGUI") ? 1 : 0, 1)
DetectHiddenWindows false
MonitorGet 1, &L, &T, &R, &B
; 1. a borderless window exactly the monitor's size: Alt+drag must not move it
fs := Gui("-Caption +AlwaysOnTop", "fsdrag fullscreen")
fs.BackColor := "202020"
fs.Show(Format("x{1} y{2} w{3} h{4} NoActivate", L, T, R - L, B - T))
Sleep 600
WinActivate fs.Hwnd
Sleep 300
cx := L + (R - L) // 2, cy := T + (B - T) // 2
MouseMove cx, cy, 0
Sleep 150
Send "{Alt down}"
Sleep 80
Send "{LButton down}"
Sleep 120
MouseMove cx + 300, cy + 200, 10
Sleep 400
Send "{LButton up}"
Sleep 80
Send "{Alt up}"
Sleep 900
WinGetPos &x, &y, &w, &h, fs.Hwnd
Check("1 fullscreen window: Alt+drag did not move it", (x = L && y = T && w = R - L && h = B - T) ? 1 : 0, 1)
fs.Destroy()
Sleep 400
; 2. an ordinary window moves as before
win := Gui("+AlwaysOnTop", "fsdrag ordinary")
win.Show(Format("x{1} y{2} w600 h400", L + 200, T + 200))
Sleep 600
WinActivate win.Hwnd
Sleep 300
WinGetPos &x0, &y0, , , win.Hwnd
MouseMove x0 + 300, y0 + 200, 0
Sleep 150
Send "{Alt down}"
Sleep 80
Send "{LButton down}"
Sleep 120
MouseMove x0 + 600, y0 + 400, 10
Sleep 400
Send "{LButton up}"
Sleep 80
Send "{Alt up}"
Sleep 1200
WinGetPos &x1, &y1, , , win.Hwnd
Check("2 ordinary window: Alt+drag moved it", (Abs(x1 - x0) > 100 || Abs(y1 - y0) > 100) ? 1 : 0, 1)
win.Destroy()
FileAppend out, A_Temp "\perf\fsdrag-test.txt"
ExitApp fails ? 1 : 0
