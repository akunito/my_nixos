#Requires AutoHotkey v2.0
#SingleInstance Force
; Win tapped alone opens the Command Palette; Hyper (Ctrl+Alt+Win) let go
; without a chord must not, whatever order the three come up in. The guard
; decided at release time and missed Win-last (reported twice, 2026-09-23).
; Run: AutoHotkey64.exe wintap-test.ahk   -> %TEMP%\perf\wintap-test.txt
SendLevel 1
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
palette := "ahk_exe Microsoft.CmdPal.UI.exe"
Shown() {
    global palette
    return WinActive(palette) ? 1 : 0
}
Dismiss() {
    global palette
    if WinActive(palette) {
        Send "{Escape}"
        Sleep 800
    }
}
DetectHiddenWindows true
Check("0 setup: the hotkey script is there", WinExist("AkuWM hotkeys ahk_class AutoHotkeyGUI") ? 1 : 0, 1)
DetectHiddenWindows false
WinActivate "ahk_class Progman"
Sleep 400
Dismiss()
Check("0 setup: no palette before the test", Shown(), 0)
; 1. Hyper let go with Win LAST (Ctrl and Alt already up when Win comes up)
Send "{Ctrl down}{Alt down}{LWin down}"
Sleep 200
Send "{Ctrl up}{Alt up}{LWin up}"
Sleep 1200
Check("1 Hyper let go, Win last: no palette", Shown(), 0)
Dismiss()
; 2. Win FIRST
Send "{Ctrl down}{Alt down}{LWin down}"
Sleep 200
Send "{LWin up}{Alt up}{Ctrl up}"
Sleep 1200
Check("2 Hyper let go, Win first: no palette", Shown(), 0)
Dismiss()
; 3. Win pressed first, then Ctrl and Alt joined it
Send "{LWin down}"
Sleep 120
Send "{Ctrl down}{Alt down}"
Sleep 200
Send "{Alt up}{Ctrl up}{LWin up}"
Sleep 1200
Check("3 Win first then Ctrl+Alt, let go: no palette", Shown(), 0)
Dismiss()
; 4. a bare tap still opens it
Send "{LWin down}"
Sleep 120
Send "{LWin up}"
Sleep 1500
Check("4 a bare Win tap opens the palette", Shown(), 1)
Dismiss()
FileAppend out, A_Temp "\perf\wintap-test.txt"
ExitApp fails ? 1 : 0
