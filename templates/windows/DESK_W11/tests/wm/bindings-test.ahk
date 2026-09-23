#Requires AutoHotkey v2.0
#SingleInstance Force
; The chords that are data (plan 10.27): bindings.tsv is re-read by the live
; hyper-desktops.ahk when the daemon posts WM_APP+1. A chord added to the file
; fires after `akuwm bindings poke`; taken out, it is gone after the next poke.
; Run: AutoHotkey64.exe bindings-test.ahk   -> %TEMP%\perf\bindings-test.txt
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
; The CLI: the unsigned copy of the dev loop, else the published one. Never
; the uiAccess exe in Program Files (a shell cannot start it, plan 10.27).
cli := EnvGet("LOCALAPPDATA") "\Programs\AkuWM\akuwm.exe"
if !FileExist(cli)
    cli := EnvGet("LOCALAPPDATA") "\Temp\akuwm-uia\akuwm-cli.exe"
tsv := EnvGet("LOCALAPPDATA") "\akuwm\bindings.tsv"
marker := A_Temp "\perf\bindings-test.marker"
CliRun(verb) {
    global cli
    RunWait('"' cli '" bindings ' verb, , "Hide")
    Sleep 700
}
DetectHiddenWindows true
Check("0 setup: the script's window is there", WinExist("AkuWM hotkeys ahk_class AutoHotkeyGUI") ? 1 : 0, 1)
; From the truth, not from whatever a previous run left in the file: the
; configuration, rendered again.
CliRun("reload")
Check("0 setup: bindings.tsv is rendered", FileExist(tsv) ? 1 : 0, 1)
rendered := FileRead(tsv)
Note("rendered has " (StrSplit(rendered, "`n").Length - 1) " lines")
Check("0 setup: no F12 chord before the test", InStr(rendered, "^!#F12") ? 1 : 0, 0)
try FileDelete marker
; 1. a chord nobody has: added to the file, then poked, it fires
try FileDelete tsv
FileAppend rendered "^!#F12`texec`t`tcmd /c echo hi > `"" marker "`"`t`n", tsv
CliRun("poke")
; Injected input is dropped while an elevated window holds the foreground
; (UIPI): the desk was left on the Administrator console once and the
; chord never arrived. The desktop is medium integrity and the hook sees
; the keys either way.
WinActivate "ahk_class Progman"
Sleep 300
Send "^!#{F12}"
Sleep 1500
Check("1 a chord added to the file fires after the poke", FileExist(marker) ? 1 : 0, 1)
; 2. rendered again from the configuration (the GUI's undo), it no longer fires
try FileDelete marker
CliRun("reload")
WinActivate "ahk_class Progman"
Sleep 300
Send "^!#{F12}"
Sleep 1500
Check("2 rendered again without it, the chord is gone", FileExist(marker) ? 1 : 0, 0)
; 3. the ones from the config are there: Hyper+X is the calculator toggle
Check("3 a chord of the configuration is in the file", InStr(rendered, "^!#x`tapp") ? 1 : 0, 1)
try FileDelete marker
FileAppend out, A_Temp "\perf\bindings-test.txt"
ExitApp fails ? 1 : 0
