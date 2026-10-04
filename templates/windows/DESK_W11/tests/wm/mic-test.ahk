#Requires AutoHotkey v2.0
#SingleInstance Force
; Hyper+M mutes and unmutes the default microphone (AkuWM `toggle-mic`) and the
; hotkey script shows "Microphone off" / "Microphone on" for a moment: Windows
; draws no sign of a muted microphone, so without the OSD the chord is blind.
; Run: AutoHotkey64.exe mic-test.ahk -> %TEMP%\perf\mic-test.txt
#Include ..\..\lib-glaze.ahk
SendLevel 1
CoordMode "Mouse", "Screen"
out := "", fails := 0
Check(name, got, want) {
    global out, fails
    ok := (got = want)
    out .= (ok ? "PASS " : "FAIL ") name " (got " got ", want " want ")`n"
    if !ok
        fails++
}
; The mixer's own answer, through Core Audio and not through the daemon, so a
; daemon that replied "muted" without muting would be caught.
; IMMDeviceEnumerator.GetDefaultAudioEndpoint(eCapture, eConsole) is slot 4,
; IMMDevice.Activate slot 3, IAudioEndpointVolume.GetMute slot 15.
MicMuted() {
    enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
    ComCall(4, enumerator, "Int", 1, "Int", 0, "Ptr*", &device := 0)
    iid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "Str", "{5CDF2C82-841E-4546-9722-0CF74078229A}", "Ptr", iid)
    ComCall(3, device, "Ptr", iid, "UInt", 23, "Ptr", 0, "Ptr*", &volume := 0)
    ComCall(15, volume, "Int*", &muted := 0)
    ObjRelease(volume), ObjRelease(device)
    return muted ? 1 : 0
}
; The OSD is a tool window: hidden to WinExist unless asked for.
OsdText() {
    DetectHiddenWindows false
    return WinExist("AkuWM OSD ahk_class AutoHotkeyGUI") ? WinGetText("AkuWM OSD ahk_class AutoHotkeyGUI") : ""
}
; Presses the chord and waits for the mixer to flip; returns the OSD text seen
; while waiting (the first non-empty one), or "" when none showed.
Press(wantMuted) {
    seen := ""
    Send "^!#m"
    t := A_TickCount
    while (A_TickCount - t < 2000) {
        if (seen = "")
            seen := Trim(OsdText(), " `r`n")
        if (MicMuted() = wantMuted && seen != "")
            break
        Sleep 50
    }
    return seen
}

DetectHiddenWindows true
Check("0 setup: the hotkey script is there", WinExist("AkuWM hotkeys ahk_class AutoHotkeyGUI") ? 1 : 0, 1)
Check("0 setup: the daemon answers on the pipe", WmPipeAlive() ? 1 : 0, 1)
DetectHiddenWindows false
WinActivate "ahk_class Progman"
Sleep 300
initial := MicMuted()
; Worked from a known state: the microphone live.
if initial {
    WmPipeAsk("compat command toggle-mic")
    Sleep 200
}
Check("0 setup: the microphone is live", MicMuted(), 0)

; 1. the chord mutes it and says so
seen := Press(1)
Check("1 Hyper+M mutes the microphone", MicMuted(), 1)
Check("1 the OSD says Microphone off", InStr(seen, "Microphone off") ? 1 : 0, 1)
; 2. the OSD goes away by itself
t := A_TickCount
while (OsdText() != "" && A_TickCount - t < 3000)
    Sleep 100
Check("2 the OSD is gone within 3 s", OsdText() = "" ? 1 : 0, 1)
; 3. the chord unmutes it and says so
seen := Press(0)
Check("3 Hyper+M unmutes the microphone", MicMuted(), 0)
Check("3 the OSD says Microphone on", InStr(seen, "Microphone on") ? 1 : 0, 1)
; 4. the reply on the pipe carries the state, for anything else that asks
reply := WmPipeAsk("compat command toggle-mic")
Check("4 the pipe reply carries muted:true", InStr(reply, '"muted":true') ? 1 : 0, 1)
Check("4 the mixer agrees", MicMuted(), 1)
reply := WmPipeAsk("compat command toggle-mic")
Check("4 and back: muted:false", InStr(reply, '"muted":false') ? 1 : 0, 1)
Check("4 the mixer agrees again", MicMuted(), 0)
; 5. the OSD never took the focus or became a managed window
Check("5 the desktop still has the focus", WinActive("ahk_class Progman") ? 1 : 0, 1)

; Left as found.
if (MicMuted() != initial)
    WmPipeAsk("compat command toggle-mic")
FileAppend out, A_Temp "\perf\mic-test.txt"
ExitApp fails ? 1 : 0
