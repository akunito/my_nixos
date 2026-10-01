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
; The daemon places a new window shortly after it appears (another monitor,
; another rectangle): put the pointer on the window as it is NOW and make sure
; it is still the window under the pointer before asking (2026-10-01: check 3
; read the desktop once, the test window had just been moved).
Over(hwnd) {
    Loop 10 {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        MouseMove x + w // 2, y + h // 2, 0
        Sleep 150
        MouseGetPos , , &under
        if (under = hwnd)
            return FullscreenUnderMouse() ? 1 : 0
    }
    global out
    out .= Format("     pointer at {1},{2} is over {3} [{4}] '{5}', not the test window{6}`n", x + w // 2, y + h // 2, ExeOf(under), WinGetClass("ahk_id " under), WinGetTitle("ahk_id " under), DllCall("IsWindowVisible", "Ptr", hwnd) ? "" : " (which is not visible)")
    return -1
}
; a journal of this test's own, never the desk's
JournalFile := A_Temp "\fsdrag-journal.tsv"
try FileDelete JournalFile
MonitorGet 1, &L, &T, &R, &B
; 1. a borderless window exactly the monitor's size. The daemon places a new
; window once it sees it -- and on the monitor of the focused workspace, not
; necessarily monitor 1 (2026-10-01: it landed on the vertical one in the full
; run); whichever monitor it ends up on, it must cover exactly that one.
fs := Gui("-Caption +AlwaysOnTop -DPIScale", "fsdrag fullscreen")
fs.BackColor := "202020"
fs.Show(Format("x{1} y{2} w{3} h{4} NoActivate", L, T, R - L, B - T))
Covers(hwnd) {
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    mon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    mi := Buffer(40, 0), NumPut("UInt", 40, mi)
    DllCall("GetMonitorInfo", "Ptr", mon, "Ptr", mi)
    mL := NumGet(mi, 4, "Int"), mT := NumGet(mi, 8, "Int"), mR := NumGet(mi, 12, "Int"), mB := NumGet(mi, 16, "Int")
    global note := Format("window {1},{2} {3}x{4} its monitor {5},{6} {7}x{8}", x, y, w, h, mL, mT, mR - mL, mB - mT)
    return (x = mL && y = mT && w = mR - mL && h = mB - mT) ? 1 : 0
}
note := ""
Loop 50 {
    Sleep 100
    if Covers(fs.Hwnd)
        break
}
out .= "     " note "`n"
Check("0 setup: the window covers the monitor it is on", Covers(fs.Hwnd), 1)
Check("1 a monitor-sized window is fullscreen", Over(fs.Hwnd), 1)
fs.Destroy()
Sleep 300
; 2. an ordinary window is not
win := Gui("+AlwaysOnTop -DPIScale", "fsdrag ordinary")
win.Show(Format("x{1} y{2} w600 h400", L + 200, T + 200))
Sleep 1500
WinActivate win.Hwnd
Sleep 300
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
