; DESK_W11 — Sway muscle memory on Windows 11 (AutoHotkey v2).
; Hyper = Ctrl+Alt+Win, exactly the Mod4+Control+Mod1 combo from user/wm/sway.
; Needs VirtualDesktopAccessor.dll (Ciantic) next to this file; Windows 11 24H2+.
;
;   Hyper+1..9,0        go to desktop N (created on demand)   = swaysome focus N
;   Hyper+Shift+1..9,0  move active window to desktop N       = swaysome move N
;   Hyper+Q / Hyper+W   previous / next desktop               = workspace-nav-prev/next
;   Hyper+Shift+Q / W   move window to previous / next desktop
;   Hyper+Tab           Task view                             = window overview
;   Hyper+Escape        close active window                   = kill
;   Hyper+F             toggle maximise                       = fullscreen
;   Hyper+Space         Start / PowerToys Run                 = rofi combi
;   Hyper+<letter>      raise-or-launch, same letters as apps/common.json
;   Alt+LeftDrag        move window                            = floating_modifier Mod1
;   Alt+RightDrag       resize window (nearest corner)
;   Hyper+Shift+Escape  suspend/resume all hotkeys (games)
;
; Elevated windows (Task Manager, installers, some launchers): a normal AHK
; process cannot move them or receive hotkeys while they are focused. Running
; the script "as administrator" fixes that but breaks drag-and-drop into
; non-elevated apps and Startup-folder autostart. The right fix is the
; UI-Access build shipped with AutoHotkey v2, which is signed and lives in
; Program Files, so Windows lets it drive elevated windows WITHOUT admin:
;   "C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe" hyper-desktops.ahk
; bootstrap.ps1 creates the Startup shortcut with that binary.
#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode 2

dll := A_ScriptDir "\VirtualDesktopAccessor.dll"
if !FileExist(dll) {
    MsgBox "VirtualDesktopAccessor.dll not found next to the script", "hyper-desktops", "Iconx"
    ExitApp
}
hVDA := DllCall("LoadLibrary", "Str", dll, "Ptr")
GoTo(n) => DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "Int", n, "Int")
Count() => DllCall("VirtualDesktopAccessor\GetDesktopCount", "Int")
Current() => DllCall("VirtualDesktopAccessor\GetCurrentDesktopNumber", "Int")
Create() => DllCall("VirtualDesktopAccessor\CreateDesktop", "Int")
MoveWin(hwnd, n) => DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber", "Ptr", hwnd, "Int", n, "Int")

EnsureDesktop(n) {
    while Count() <= n
        Create()
}
Go(n) {
    EnsureDesktop(n)
    GoTo(n)
}
Move(n) {
    EnsureDesktop(n)
    MoveWin(WinGetID("A"), n)
    GoTo(n)
}
Rel(delta) {
    c := Count(), i := Mod(Current() + delta + c, c)
    GoTo(i)
}
RelMove(delta) {
    c := Count(), i := Mod(Current() + delta + c, c)
    MoveWin(WinGetID("A"), i)
    GoTo(i)
}

; Hyper = ^!# (Ctrl Alt Win). Hyper+Shift = ^!#+
Loop 9 {
    k := A_Index
    Hotkey "^!#" k, (*) => Go(k - 1)
    Hotkey "^!#+" k, (*) => Move(k - 1)
}
^!#0:: Go(9)
^!#+0:: Move(9)
^!#q:: Rel(-1)
^!#w:: Rel(+1)
^!#+q:: RelMove(-1)
^!#+w:: RelMove(+1)
^!#Tab:: Send "#{Tab}"
^!#Escape:: WinClose "A"
^!#f:: {
    h := WinGetID("A")
    WinGetMinMax(h) = 1 ? WinRestore(h) : WinMaximize(h)
}
^!#Space:: Send "!{Space}" ; PowerToys Run (falls back to nothing if not installed) — change to "#" for Start

; raise-or-launch — the app-toggle.sh idea: focus if running, minimise if focused, launch otherwise
Toggle(exe, cmd) {
    if WinExist("ahk_exe " exe) {
        if WinActive("ahk_exe " exe)
            WinMinimize
        else
            WinActivate
    } else {
        Run cmd
    }
}
^!#t:: Toggle("WindowsTerminal.exe", "wt.exe")
^!#z:: Toggle("zen.exe", "zen")
^!#v:: Toggle("vivaldi.exe", "vivaldi")
^!#l:: Toggle("Telegram.exe", A_AppData "\..\Roaming\Telegram Desktop\Telegram.exe")
^!#d:: Toggle("Obsidian.exe", A_LocalAppData "\Obsidian\Obsidian.exe")
^!#c:: Toggle("Code.exe", "code")
^!#p:: Toggle("Bitwarden.exe", A_LocalAppData "\Programs\Bitwarden\Bitwarden.exe")
^!#o:: Toggle("Element.exe", A_LocalAppData "\element-desktop\Element.exe")
^!#y:: Toggle("Spotify.exe", "spotify:")
^!#x:: Toggle("CalculatorApp.exe", "calc")
^!#e:: Toggle("explorer.exe", "explorer")
^!#u:: Toggle("dbeaver.exe", "dbeaver")
^!#+r:: Reload
^!#+Escape:: Suspend

; ---- Alt+drag: move (left) / resize (right), Sway's floating_modifier ----
; Skips maximised windows, the desktop and the taskbar. Resize grabs the corner
; nearest to the pointer, like sway. Uses the raw event loop (no admin needed).
AltDrag(mode) {
    MouseGetPos &mx, &my, &hwnd
    if !hwnd
        return
    cls := WinGetClass("ahk_id " hwnd)
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd" || WinGetMinMax("ahk_id " hwnd) = 1)
        return
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    WinActivate "ahk_id " hwnd
    if (mode = "resize") {
        left := (mx - wx) < (ww / 2), top := (my - wy) < (wh / 2)
    }
    btn := mode = "move" ? "LButton" : "RButton"
    SetWinDelay -1
    while GetKeyState(btn, "P") {
        MouseGetPos &cx, &cy
        dx := cx - mx, dy := cy - my
        if (mode = "move") {
            WinMove wx + dx, wy + dy, , , "ahk_id " hwnd
        } else {
            nx := left ? wx + dx : wx
            ny := top ? wy + dy : wy
            nw := left ? ww - dx : ww + dx
            nh := top ? wh - dy : wh + dy
            if (nw > 150 && nh > 100)
                WinMove nx, ny, nw, nh, "ahk_id " hwnd
        }
        Sleep 8
    }
}
!LButton:: AltDrag("move")
!RButton:: AltDrag("resize")
