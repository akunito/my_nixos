#Requires AutoHotkey v2.0
#SingleInstance Force
; The settings window (M5): Hyper+S shows and hides it, a section can be
; asked for by name, and `--smoke` opens every section on the real desk and
; round-trips a rule through its editor and the daemon.
; Run: AutoHotkey64.exe gui-test.ahk   -> %TEMP%\perf\gui-test.txt
SendLevel 1
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
exe := EnvGet("LOCALAPPDATA") "\Programs\AkuWM\akuwm-gui.exe"
win := "AkuWM ahk_exe akuwm-gui.exe"
Check("0 setup: akuwm-gui.exe is published", FileExist(exe) ? 1 : 0, 1)
if !ProcessExist("akuwm-gui.exe") {
    Run '"' exe '" --hidden'
    Sleep 4000
}
Check("0 setup: the tray instance is running", ProcessExist("akuwm-gui.exe") ? 1 : 0, 1)
if WinExist(win) {
    Run '"' exe '" --toggle'
    Sleep 1000
}
Check("0 setup: the window starts hidden", WinExist(win) ? 1 : 0, 0)
WinActivate "ahk_class Progman"
Sleep 300
; 1. Hyper+S shows it
Send "^!#s"
Sleep 2000
Check("1 Hyper+S shows the window", WinExist(win) ? 1 : 0, 1)
Check("1 and it is the active window", WinActive(win) ? 1 : 0, 1)
; 2. Hyper+S again hides it
Send "^!#s"
Sleep 1200
Check("2 Hyper+S again hides it", WinExist(win) ? 1 : 0, 0)
; 3. a section by name, then the toggle from the command line
Run '"' exe '" --section monitors'
Sleep 2000
Check("3 --section monitors shows it", WinExist(win) ? 1 : 0, 1)
Run '"' exe '" --toggle'
Sleep 1200
Check("3 --toggle from a second launch hides it", WinExist(win) ? 1 : 0, 0)
; 4. the smoke: every section, and a rule round trip through the daemon
smoke := A_Temp "\perf\gui-smoke.txt"
try FileDelete smoke
Run '"' exe '" --smoke "' smoke '"'
waited := 0
while (!FileExist(smoke) && waited < 40000) {
    Sleep 500
    waited += 500
}
Sleep 500
if FileExist(smoke) {
    Loop Parse FileRead(smoke), "`n", "`r" {
        if (A_LoopField = "")
            continue
        failed := InStr(A_LoopField, "FAIL") = 1
        if failed
            fails++
        out .= (failed ? "FAIL " : "PASS ") "4 smoke: " SubStr(A_LoopField, 6) "`n"
    }
} else {
    out .= "FAIL 4 smoke: no result after 40 s`n"
    fails++
}
FileAppend out, A_Temp "\perf\gui-test.txt"
ExitApp fails ? 1 : 0
