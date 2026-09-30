#Requires AutoHotkey v2.0
; Recovery tool: merges every native Windows virtual desktop into the first one
; (RemoveDesktop moves their windows to desktop 0). Needed when windows end up on
; native desktops GlazeWM cannot see (it manages only the current native desktop):
; symptom = focusing such a window "throws you out" of the GlazeWM workspaces.
; Run it, then restart GlazeWM. Writes a log to %TEMP%\vd-merge.txt.
dll := A_ScriptDir "\VirtualDesktopAccessor.dll"
DllCall("LoadLibrary", "Str", dll, "Ptr")
DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "Int", 0, "Int")
n := DllCall("VirtualDesktopAccessor\GetDesktopCount", "Int")
out := "before: " n " desktops`n"
Loop n - 1 {
    i := n - A_Index
    r := DllCall("VirtualDesktopAccessor\RemoveDesktop", "Int", i, "Int", 0, "Int")
    out .= "remove desktop " i " -> " r "`n"
}
out .= "after: " DllCall("VirtualDesktopAccessor\GetDesktopCount", "Int") " desktops`n"
FileAppend out, A_Temp "\vd-merge.txt", "UTF-8"
