#Requires AutoHotkey v2.0
#SingleInstance Force
; Alt+drag leaves a fullscreen window alone (Alt is the game's own pointer key;
; dragging Aion 2 pulled it out of fullscreen, 2026-09-30). The gesture itself
; cannot be faked from a script (it polls the PHYSICAL button), so what is
; checked is the predicate its #HotIf asks: FullscreenUnderMouse(), by the two
; routes it has -- a window exactly the size of its monitor, and a window the
; daemon's journal marks "fullscreen" -- and that an ordinary window is neither.
; Run: AutoHotkey64.exe fsdrag-test.ahk -> %TEMP%\perf\fsdrag-test.txt
#Include ..\..\lib-layout-journal.ahk
SendLevel 1
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
Over(hwnd) {
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    MouseMove x + w // 2, y + h // 2, 0
    Sleep 120
    return FullscreenUnderMouse() ? 1 : 0
}
; a journal of this test's own, never the desk's
JournalFile := A_Temp "\fsdrag-journal.tsv"
try FileDelete JournalFile
MonitorGet 1, &L, &T, &R, &B
; 1. a borderless window exactly the monitor's size
fs := Gui("-Caption +AlwaysOnTop -DPIScale", "fsdrag fullscreen")
fs.BackColor := "202020"
fs.Show(Format("x{1} y{2} w{3} h{4} NoActivate", L, T, R - L, B - T))
; The daemon places a new window once it sees it (a floating one covering the
; monitor is given the whole monitor); wait for the rectangle to settle.
Loop 50 {
    Sleep 100
    WinGetPos &x, &y, &w, &h, fs.Hwnd
    if (x = L && y = T && w = R - L && h = B - T)
        break
}
out .= Format("     window {1},{2} {3}x{4} monitor {5},{6} {7}x{8}`n", x, y, w, h, L, T, R - L, B - T)
Check("0 setup: the window is the monitor's size", (x = L && y = T && w = R - L && h = B - T) ? 1 : 0, 1)
Check("1 a monitor-sized window is fullscreen", Over(fs.Hwnd), 1)
fs.Destroy()
Sleep 300
; 2. an ordinary window is not
win := Gui("+AlwaysOnTop -DPIScale", "fsdrag ordinary")
win.Show(Format("x{1} y{2} w600 h400 NoActivate", L + 200, T + 200))
Sleep 500
Check("2 an ordinary window is not fullscreen", Over(win.Hwnd), 0)
; 3. the same window, once the journal says fullscreen for its process|class
key := StrLower(RegExReplace(ExeOf(win.Hwnd), "i)\.exe$", "")) "|" WinGetClass("ahk_id " win.Hwnd)
FileAppend key "`t\\.\DISPLAY1`t10`tfullscreen`t0`t0`t0`t100`t100`t0`t0`t100`t100`t20260930193652`n", JournalFile, "UTF-8"
Sleep 50
Check("3 a window the journal marks fullscreen is fullscreen", Over(win.Hwnd), 1)
; 4. journal says floating again: not fullscreen (the cache follows the file)
Sleep 1100   ; FileGetTime is per second; a same-second rewrite of equal size would hit the cache
try FileDelete JournalFile
FileAppend key "`t\\.\DISPLAY1`t10`tfloating`t0`t0`t0`t100`t100`t0`t0`t100`t100`t20260930193652`n", JournalFile, "UTF-8"
Sleep 50
Check("4 journal back to floating: not fullscreen", Over(win.Hwnd), 0)
win.Destroy()
try FileDelete JournalFile
FileAppend out, A_Temp "\perf\fsdrag-test.txt"
ExitApp fails ? 1 : 0
