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
; v2 defaults Mouse coords to the active window's CLIENT area; WinGetPos/WinMove
; are screen coords. Mixing them made Alt+drag feed the window's own motion back
; into the delta (flicker/jumps). Everything below assumes screen coords.
CoordMode "Mouse", "Screen"
#SingleInstance Force
SetTitleMatchMode 2

dll := A_ScriptDir "\VirtualDesktopAccessor.dll"
if !FileExist(dll) {
    MsgBox "VirtualDesktopAccessor.dll not found next to the script", "hyper-desktops", "Iconx"
    ExitApp
}
hVDA := DllCall("LoadLibrary", "Str", dll, "Ptr")
; ---- GlazeWM: workspaces, focus, move, layout (the Sway bindings) ----
; GlazeWM owns the windows (tiling by default, per-monitor workspaces 10-19 on
; the main monitor, 20-29 on the vertical one; config in glazewm\config.yaml).
; It has no keybindings of its own: every chord below shells to its CLI, which
; keeps the Hyper layer in this file and the Win key usable. Hyper+N follows the
; swaysome rule from Sway: it acts on the monitor that has the focus.
glazeExe := A_ProgramFiles "\glzr.io\GlazeWM\cli\glazewm.exe"
Glaze(args) => Run('"' glazeExe '" command ' args, , "Hide")
PrimaryMon() => DllCall("MonitorFromPoint", "Int64", 0, "UInt", 1, "Ptr")
FocusGroup() {  ; 1 = main monitor (1x), 2 = secondary (2x)
    h := WinExist("A")
    if h && WinGetClass("ahk_id " h) != "Progman" && WinGetClass("ahk_id " h) != "WorkerW"
        mon := DllCall("MonitorFromWindow", "Ptr", h, "UInt", 2, "Ptr")
    else {
        MouseGetPos &mx, &my
        mon := DllCall("MonitorFromPoint", "Int64", (my << 32) | (mx & 0xFFFFFFFF), "UInt", 2, "Ptr")
    }
    return mon = PrimaryMon() ? 1 : 2
}
Ws(n) => FocusGroup() * 10 + Mod(n, 10)   ; Hyper+1..9 -> x1..x9, Hyper+0 -> x0
Loop 10 {
    k := Mod(A_Index, 10)
    Hotkey "^!#" k, ((n) => (*) => Glaze("focus --workspace " Ws(n)))(k)
    Hotkey "^!#+" k, ((n) => (*) => Glaze("move --workspace " Ws(n)))(k)
}
^!#q:: Glaze("focus --prev-active-workspace-on-monitor")
^!#w:: Glaze("focus --next-active-workspace-on-monitor")
^!#+q:: Glaze("move --prev-active-workspace-on-monitor")
^!#+w:: Glaze("move --next-active-workspace-on-monitor")
^!#Left:: Glaze("focus --monitor 0")          ; focus output left/right (main is left)
^!#Right:: Glaze("focus --monitor 1")
^!#+Left:: Glaze("move --workspace-in-direction left")
^!#+Right:: Glaze("move --workspace-in-direction right")
^!#h:: Glaze("focus --direction left")        ; sway: h/j/k + ? for right (l is an app)
^!#j:: Glaze("focus --direction down")
^!#k:: Glaze("focus --direction up")
^!#+/:: Glaze("focus --direction right")
^!#+j:: Glaze("move --direction left")        ; sway window-move.sh: Shift+j/:/k/l
^!#+;:: Glaze("move --direction right")
^!#+k:: Glaze("move --direction down")
^!#+l:: Glaze("move --direction up")
^!#+u:: Glaze("resize --width -5%")
^!#+p:: Glaze("resize --width +5%")
^!#+i:: Glaze("resize --height +5%")
^!#+o:: Glaze("resize --height -5%")
^!#Escape:: Glaze("close")
^!#f:: Glaze("toggle-fullscreen")
^!#+g:: Glaze("toggle-fullscreen")
^!#+f:: Glaze("toggle-floating")
^!#+Space:: Glaze("toggle-floating")
^!#+v:: Glaze("toggle-tiling-direction")     ; sway split toggle (Shift+v is cliphist there; Win+V here)
^!#+-:: Glaze("toggle-minimized")            ; scratchpad stand-in
^!#Tab:: Send "#{Tab}"
^!#Space:: Send "#!{Space}" ; PowerToys Command Palette (its own hotkey is Win+Alt+Space; PowerToys Run is disabled) — rofi stand-in

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
^!#z:: Toggle("zen.exe", A_ProgramFiles "\Zen Browser\zen.exe")
^!#v:: Toggle("vivaldi.exe", EnvGet("LOCALAPPDATA") "\Vivaldi\Application\vivaldi.exe")
^!#l:: Toggle("Telegram.exe", A_AppData "\Telegram Desktop\Telegram.exe")
^!#d:: Toggle("Obsidian.exe", EnvGet("LOCALAPPDATA") "\Programs\Obsidian\Obsidian.exe")
^!#c:: Toggle("Code.exe", "code")
^!#p:: Toggle("Bitwarden.exe", EnvGet("LOCALAPPDATA") "\Programs\Bitwarden\Bitwarden.exe")
^!#o:: Toggle("Element.exe", EnvGet("LOCALAPPDATA") "\element-desktop\Element.exe")
^!#y:: Toggle("Spotify.exe", A_AppData "\Spotify\Spotify.exe")
^!#x:: Toggle("CalculatorApp.exe", "calc")
^!#e:: Toggle("explorer.exe", "explorer")
^!#u:: Toggle("dbeaver.exe", EnvGet("LOCALAPPDATA") "\DBeaver\dbeaver.exe")
; ShareX cannot RegisterHotKey Ctrl+Alt+Shift+Win+<letter> (Windows keeps that set for
; the "Office key"), so the hook-based AHK owns Hyper+Shift+C and runs the workflow.
^!#+c:: Run '"' A_ProgramFiles '\ShareX\ShareX.exe" -workflow "Hyper+Shift+C"'
; ---- Hyper+Shift+Backspace: power menu, the rofi-power-mode.sh of Sway ----
; (Hyper+Shift+Return is Windows' own Copilot/Office chord and is left alone.)
; A dark list in the middle of the screen; arrows/Enter/Esc, or type the first
; letter. Hibernate is left out on purpose: bootstrap.ps1 runs `powercfg /h off`
; (Fast Startup off protects the NTFS drives NixOS mounts).
PowerMenu() {
    static items := ["Lock", "Logout", "Reboot", "Shutdown", "Suspend"]
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Power")
    g.BackColor := "1e1e2e"
    g.SetFont("s14 cE0DEF4", "Segoe UI")
    lb := g.Add("ListBox", "w260 r5 Background313244 -VScroll", items)
    lb.Choose(1)
    run := (*) => (choice := lb.Text, g.Destroy(), PowerAction(choice))
    lb.OnEvent("DoubleClick", run)
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    HotIfWinActive("Power ahk_class AutoHotkeyGUI")
    Hotkey "Enter", run, "On"
    Hotkey "Space", run, "On"
    for i, item in items
        Hotkey SubStr(item, 1, 1), ((idx) => (*) => (lb.Choose(idx), run()))(i), "On"
    HotIfWinActive()
    g.Show("AutoSize Center")
}
PowerAction(choice) {
    switch choice {
        case "Lock":     DllCall("user32\LockWorkStation")
        case "Logout":   Shutdown 0
        case "Reboot":   Shutdown 2
        case "Shutdown": Shutdown 9      ; 1 shutdown + 8 power off
        case "Suspend":  DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
    }
}
^!#+Backspace:: PowerMenu()
; ---- Win tapped alone -> Command Palette instead of the Start menu ----
; Pressing Win sends an unassigned virtual key (vkE8) while Win is held, so
; Windows thinks a Win+<key> chord happened and does not open Start on release.
; Win+E / Win+L / the Hyper chords pass through untouched (~). On release, if no
; physical key was pressed in between (A_PriorKey ignores keys sent by AHK), open
; the palette. Delete these two hotkeys to get the Start menu back.
~LWin:: Send "{Blind}{vkE8}"
~LWin Up:: {
    if (A_PriorKey = "LWin")
        Send "#!{Space}"
}
; (Hyper+Shift+S "sticky" has no GlazeWM equivalent — Windows virtual desktops are
;  not used any more, so the VirtualDesktopAccessor pin is gone too.)
^!#+r:: {
    Glaze("wm-reload-config")
    Reload
}
^!#+Escape:: {
    Glaze("wm-toggle-pause")
    Suspend
}

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
