#Requires AutoHotkey v2.0
#SingleInstance Force
; Hyper+CapsLock forces Caps Lock off, Hyper+Shift+CapsLock toggles it. Caps
; Lock came on by itself on 2026-09-30 and no key cleared it; the chord is the
; way out that needs no shell.
; Run: AutoHotkey64.exe capslock-test.ahk -> %TEMP%\perf\capslock-test.txt
SendLevel 1
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
; 1. stuck on, Hyper+CapsLock clears it
SetCapsLockState "On"
Sleep 150
Check("1 setup: Caps Lock is on", Caps(), 1)
Send "^!#{CapsLock}"
Sleep 500
Check("1 Hyper+CapsLock turns it off", Caps(), 0)
; 2. already off, the chord leaves it off (never a toggle)
Send "^!#{CapsLock}"
Sleep 500
Check("2 Hyper+CapsLock on an off Caps Lock keeps it off", Caps(), 0)
; 3. Hyper+Shift+CapsLock toggles, both ways
Send "^!#+{CapsLock}"
Sleep 500
Check("3 Hyper+Shift+CapsLock turns it on", Caps(), 1)
Send "^!#+{CapsLock}"
Sleep 500
Check("3 Hyper+Shift+CapsLock turns it off again", Caps(), 0)
SetCapsLockState "Off"
FileAppend out, A_Temp "\perf\capslock-test.txt"
ExitApp fails ? 1 : 0
