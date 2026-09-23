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
cli := "C:\Program Files\AkuWM\akuwm-cli.exe"
tsv := EnvGet("LOCALAPPDATA") "\akuwm\bindings.tsv"
marker := A_Temp "\perf\bindings-test.marker"
Poke() {
    global cli
    RunWait('"' cli '" bindings poke', , "Hide")
    Sleep 700
}
DetectHiddenWindows true
Check("0 setup: the script's window is there", WinExist("AkuWM hotkeys ahk_class AutoHotkeyGUI") ? 1 : 0, 1)
Check("0 setup: bindings.tsv is rendered", FileExist(tsv) ? 1 : 0, 1)
original := FileExist(tsv) ? FileRead(tsv) : ""
Note("original has " (StrSplit(original, "`n").Length - 1) " lines")
try FileDelete marker
; 1. a chord nobody has: added to the file, then poked, it fires
try FileDelete tsv
FileAppend original "^!#F12`texec`t`tcmd /c echo hi > `"" marker "`"`t`n", tsv
Poke()
Send "^!#{F12}"
Sleep 1500
Check("1 a chord added to the file fires after the poke", FileExist(marker) ? 1 : 0, 1)
; 2. taken out and poked again, it no longer fires
try FileDelete marker
try FileDelete tsv
FileAppend original, tsv
Poke()
Send "^!#{F12}"
Sleep 1500
Check("2 taken out of the file, the chord is gone after the poke", FileExist(marker) ? 1 : 0, 0)
; 3. the ones from the config are still bound: Hyper+X is the calculator toggle
Check("3 an original chord is still in the file", InStr(original, "^!#x`tapp") ? 1 : 0, 1)
try FileDelete marker
FileAppend out, A_Temp "\perf\bindings-test.txt"
ExitApp fails ? 1 : 0
