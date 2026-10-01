#Requires AutoHotkey v2.0
#SingleInstance Force
; Hyper+Shift+M forces Caps Lock off. Caps Lock came on by itself on
; 2026-09-30 and no key cleared it; the chord is the way out that needs no
; shell.
; Run: AutoHotkey64.exe capslock-test.ahk -> %TEMP%\perf\capslock-test.txt
SendLevel 1
; Send turns Caps Lock off for the duration of a Send and puts it BACK
; afterwards (SetStoreCapsLockMode, default on): with it the chord's handler
; ran, logged "now off", and the test read Caps Lock on again 600 ms later
; (2026-10-01 10:25, trace). The test must not restore what it is testing.
SetStoreCapsLockMode false
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
Caps() => GetKeyState("CapsLock", "T") ? 1 : 0
DetectHiddenWindows true
Check("0 setup: the hotkey script is there", WinExist("AkuWM hotkeys ahk_class AutoHotkeyGUI") ? 1 : 0, 1)
DetectHiddenWindows false
WinActivate "ahk_class Progman"
Sleep 300
; 1. stuck on, Hyper+Shift+M clears it
SetCapsLockState "On"
Sleep 150
Check("1 setup: Caps Lock is on", Caps(), 1)
Send "^!#+m"
Sleep 500
Check("1 Hyper+Shift+M turns it off", Caps(), 0)
; 2. already off, the chord leaves it off (never a toggle)
Send "^!#+m"
Sleep 500
Check("2 Hyper+Shift+M on an off Caps Lock keeps it off", Caps(), 0)
; 3. the chord does not type an m anywhere (Notepad would show it)
SetCapsLockState "On"
Sleep 150
Send "^!#+m"
Sleep 500
Check("3 a second stuck Caps Lock is cleared too", Caps(), 0)
SetCapsLockState "Off"
FileAppend out, A_Temp "\perf\capslock-test.txt"
ExitApp fails ? 1 : 0
