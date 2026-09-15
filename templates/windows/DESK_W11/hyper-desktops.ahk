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
; AHK is system-DPI aware (150 % here): monitor 1 is 0..3840 in real pixels, the
; vertical monitor is virtualised to 4608..6336 x -490..2582 (1440 px x 1.2). Mouse,
; WinGetPos and WinMove all share that space, so they stay consistent; only raw
; physical numbers typed by hand are wrong there (see tests/ahk-space.ahk).
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
; ---- GlazeWM (floating only): per-monitor, independent workspaces ----
; 10-19 on the main monitor, 20-29 on the vertical one (Sway's swaysome
; numbers). GlazeWM has no keybindings of its own; the chords below shell to
; its CLI. Hyper+N acts on the monitor that has the focus, like swaysome.
glazeExe := A_ProgramFiles "\glzr.io\GlazeWM\cli\glazewm.exe"
Glaze(args) => RunWait('"' glazeExe '" command ' args, , "Hide")
GlazeQuery(what) {
    tmp := A_Temp "\glazewm-query.json"
    RunWait(A_ComSpec ' /c ""' glazeExe '" query ' what ' > "' tmp '""', , "Hide")
    return FileRead(tmp, "UTF-8")
}
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
; Hyper+Q/W: previous/next workspace inside the focused monitor's group, wrapping
; (Sway's workspace-nav scripts). Shift moves the window there and follows it.
CurrentWs(group) {
    j := GlazeQuery("monitors"), pos := 1
    while pos := RegExMatch(j, '"name":"(\d+)"[\s\S]*?"isDisplayed":(true|false)', &m, pos) {
        if (m[2] = "true" && SubStr(m[1], 1, 1) = group)
            return m[1]
        pos += StrLen(m[0])
    }
    return group "1"
}
WsCycle(delta, move := false) {
    g := FocusGroup(), cur := CurrentWs(g), i := 1
    order := [g "1", g "2", g "3", g "4", g "5", g "6", g "7", g "8", g "9", g "0"]
    for k, v in order
        if (v = cur)
            i := k
    n := order[Mod(i - 1 + delta + 10, 10) + 1]
    if move
        Glaze("move --workspace " n)
    Glaze("focus --workspace " n)
}
^!#q:: WsCycle(-1)
^!#w:: WsCycle(+1)
^!#+q:: WsCycle(-1, true)
^!#+w:: WsCycle(+1, true)
^!#Left:: Glaze("focus --monitor 0")          ; focus output left/right (main is left)
^!#Right:: Glaze("focus --monitor 1")
^!#+Left:: Glaze("move --workspace-in-direction left")
^!#+Right:: Glaze("move --workspace-in-direction right")
; ---- Hyper+Tab / Win+Tab: overview of every window in every GlazeWM workspace ----
; The Task View replacement. Typing filters (ListBox type-ahead), Enter or double
; click focuses the window (GlazeWM switches that monitor to its workspace).
WinSwitcher() {
    j := GlazeQuery("workspaces"), items := [], ids := [], ws := "?", pos := 1
    pat := '"type":"workspace","id":"[^"]+","name":"(\d+)"|"type":"window","id":"([^"]+)"[\s\S]*?"title":"((?:[^"\\]|\\.)*)","className":"[^"]*","processName":"([^"]*)"'
    while pos := RegExMatch(j, pat, &m, pos) {
        if m[1]
            ws := m[1]
        else if (m[3] != "") {
            items.Push("[" ws "]  " m[4] "  —  " StrReplace(SubStr(m[3], 1, 70), '\"', '"'))
            ids.Push(m[2])
        }
        pos += StrLen(m[0])
    }
    if !items.Length
        return
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Windows")
    g.BackColor := "1e1e2e"
    g.SetFont("s12 cE0DEF4", "Segoe UI")
    lb := g.Add("ListBox", "w900 r" Min(items.Length, 18) " Background313244", items)
    lb.Choose(1)
    go := (*) => (i := lb.Value, g.Destroy(), i ? Glaze("focus --container-id " ids[i]) : 0)
    lb.OnEvent("DoubleClick", go)
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    HotIfWinActive("Windows ahk_class AutoHotkeyGUI")
    Hotkey "Enter", go, "On"
    HotIfWinActive()
    g.Show("AutoSize Center")
}
^!#Tab:: WinSwitcher()
#Tab:: WinSwitcher()
; Native virtual desktops must not be created or switched while GlazeWM runs
; (windows on another native desktop are invisible to it): swallow the chords.
^#d:: return
^#Left:: return
^#Right:: return
^#F4:: return
^!#Escape:: WinClose "A"
^!#f:: {
    h := WinGetID("A")
    WinGetMinMax(h) = 1 ? WinRestore(h) : WinMaximize(h)
}
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
; ---- Ctrl+Alt+C in Windows Terminal: last Claude Code answer -> Notepad++ ----
; Claude Code has no keybinding action for /copy, so this types the slash command,
; waits for the clipboard to change (the fullscreen picker may ask which block:
; answer it, the macro keeps waiting up to 20 s) and opens the text in a fresh
; Notepad++ instance. Copying from the terminal breaks on the rendered wraps,
; this does not. The input box must be empty when you press it.
CopyLastToNpp() {
    A_Clipboard := ""
    Send "/copy{Enter}"
    if !ClipWait(20) {
        TrayTip "Nothing copied (clipboard stayed empty)", "Claude Code /copy", 2
        return
    }
    file := A_Temp "\claude-last-response.md"
    try FileDelete file
    FileAppend A_Clipboard, file, "UTF-8-RAW"
    Run '"' A_ProgramFiles '\Notepad++\notepad++.exe" -multiInst -nosession "' file '"'
}
#HotIf WinActive("ahk_exe WindowsTerminal.exe")
^!c:: CopyLastToNpp()
#HotIf
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
; (no "sticky": GlazeWM workspaces replace Windows virtual desktops here)
^!#+r:: Reload
^!#+Escape:: Suspend

; ---- Alt+drag: move (left) / resize (right), Sway's floating_modifier ----
; Skips maximised windows, the desktop and the taskbar. Resize grabs the corner
; nearest to the pointer, like sway. Uses the raw event loop (no admin needed).
; After a placement that may leave a per-monitor-DPI app fighting with GlazeWM
; (the size storm seen on the vertical monitor), watch 1.5 s and put the size
; back, size-only (that sticks), at most 3 times. Logged.
Watchdog(hwnd, ww, wh) {
    fixes := 0
    Loop 75 {
        Sleep 20
        try WinGetPos , , &w, &h, "ahk_id " hwnd
        catch
            return
        if ((w != ww || h != wh) && WinGetMinMax("ahk_id " hwnd) = 0) {
            if (++fixes > 3) {
                FileAppend Format("{1} watchdog {2}: giving up at {3}x{4}`n", A_Now, WinGetProcessName("ahk_id " hwnd), w, h), A_Temp "\altdrag.log"
                return
            }
            WinMove , , ww, wh, "ahk_id " hwnd
            FileAppend Format("{1} watchdog {2}: {3}x{4} -> {5}x{6} (fix {7})`n", A_Now, WinGetProcessName("ahk_id " hwnd), w, h, ww, wh, fixes), A_Temp "\altdrag.log"
        }
    }
}
AltDrag(mode) {
    MouseGetPos &mx, &my, &hwnd
    if !hwnd
        return
    cls := WinGetClass("ahk_id " hwnd)
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd")
        return
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    WinActivate "ahk_id " hwnd
    fromMax := (WinGetMinMax("ahk_id " hwnd) = 1)
    if fromMax {
        ; Maximised: restore first and keep the grab point at the same relative spot
        ; under the cursor (what Windows does when you drag a maximised title bar),
        ; then carry on with the normal drag/resize. Windows' own restore rectangle
        ; (GetWindowPlacement.rcNormalPosition, read while still maximised) is the
        ; authority for the size: a per-monitor-DPI app can come out of maximised
        ; rescaled, and once that happened to Discord the rectangle grew x1.5 per
        ; gesture (1171 -> 8946 px high). If the rectangle itself is already bigger
        ; than the monitor, it is poisoned: shrink it to 80 % of the work area.
        fx := (mx - wx) / ww, fy := (my - wy) / wh
        wp := Buffer(44, 0), NumPut("UInt", 44, wp, 0)
        DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)
        nw := NumGet(wp, 36, "Int") - NumGet(wp, 28, "Int"), nh := NumGet(wp, 40, "Int") - NumGet(wp, 32, "Int")
        MonitorGetWorkArea(1, &al, &at, &ar, &ab)
        Loop MonitorGetCount() {
            MonitorGet A_Index, &ml, &mt, &mr, &mb
            if (mx >= ml && mx < mr && my >= mt && my < mb)
                MonitorGetWorkArea A_Index, &al, &at, &ar, &ab
        }
        if (nw > ar - al || nh > ab - at || nw < 200 || nh < 150)
            nw := Round((ar - al) * 0.8), nh := Round((ab - at) * 0.8)
        WinRestore "ahk_id " hwnd
        lw := -1, lh := -1, stable := 0
        Loop 80 {   ; not maximised AND size unchanged for 3 reads (measured ~170-200 ms)
            Sleep 5
            WinGetPos , , &rw, &rh, "ahk_id " hwnd
            if (WinGetMinMax("ahk_id " hwnd) = 0 && rw = lw && rh = lh) {
                if (++stable >= 3)
                    break
            } else
                stable := 0
            lw := rw, lh := rh
        }
        ww := nw, wh := nh
        wx := Round(mx - fx * ww), wy := Max(Round(my - fy * wh), at)
        ; ONE SetWindowPos with position AND size: measured, two separate calls let
        ; the app rescale between them (3072x1694 came out 2708x1744), one call sticks.
        WinMove wx, wy, ww, wh, "ahk_id " hwnd
        FileAppend Format("{1} max-restore {2}: normal={3}x{4} came-out={5}x{6} -> {7}x{8}`n", A_Now, WinGetProcessName("ahk_id " hwnd), nw, nh, rw, rh, ww, wh), A_Temp "\altdrag.log"
    }
    if (mode = "resize") {
        left := (mx - wx) < (ww / 2), top := (my - wy) < (wh / 2)
    }
    btn := mode = "move" ? "LButton" : "RButton"
    SetWinDelay -1
    mon0 := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    MonAt(px, py) => DllCall("MonitorFromPoint", "Int64", (py << 32) | (px & 0xFFFFFFFF), "UInt", 2, "Ptr")
    ghost := "", topZone := false, unstable := false
    WorkAreaAt(px, py, &l, &t, &r, &b) {
        Loop MonitorGetCount() {
            MonitorGet A_Index, &ml, &mt, &mr, &mb
            if (px >= ml && px < mr && py >= mt && py < mb) {
                MonitorGetWorkArea A_Index, &l, &t, &r, &b
                return true
            }
        }
        return false
    }
    while GetKeyState(btn, "P") {
        MouseGetPos &cx, &cy
        dx := cx - mx, dy := cy - my
        if (mode = "move") {
            ; Live-move only inside the starting monitor. Measured 2026-09-15: once the
            ; window is on the other monitor, EVERY position-only WinMove makes a
            ; per-monitor-DPI app (Discord/Electron) rescale again, cumulatively
            ; (1656x1216 -> 3199x28131 in 60 steps). So across the boundary a
            ; translucent outline follows the cursor instead, and the real window
            ; jumps once on release.
            if !ghost {
                ghost := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")   ; click-through, layered; -DPIScale = raw pixels (measured: default is x1.5)
                ghost.BackColor := "c4a7e7"
                WinSetTransparent 90, ghost
            }
            ; Top zone (<= 6 px under the top of the work area): the outline becomes
            ; the whole work area and the release maximises there (sway/Windows snap).
            topZone := WorkAreaAt(cx, cy, &al, &at, &ar, &ab) && (cy - at) <= 6
            if topZone {
                ghost.Show("NA x" al " y" at " w" (ar - al) " h" (ab - at))
            } else if (MonAt(cx, cy) = mon0 && !unstable) {
                ghost.Hide()
                WinMove wx + dx, wy + dy, , , "ahk_id " hwnd
                ; Storm guard: if the app answered a plain move with a rescale (stale
                ; DPI context, seen on the vertical monitor), stop touching it and
                ; finish the drag as an outline; placement happens once on release.
                WinGetPos , , &gw, &gh, "ahk_id " hwnd
                if (gw != ww || gh != wh) {
                    unstable := true
                    FileAppend Format("{1} storm-guard {2}: rescaled to {3}x{4} during move (expected {5}x{6})`n", A_Now, WinGetProcessName("ahk_id " hwnd), gw, gh, ww, wh), A_Temp "\altdrag.log"
                }
            } else {
                ghost.Show("NA x" (cx - (mx - wx)) " y" (cy - (my - wy)) " w" ww " h" wh)
            }
        } else {
            nx := left ? wx + dx : wx
            ny := top ? wy + dy : wy
            nw := left ? ww - dx : ww + dx
            nh := top ? wh - dy : wh + dy
            if (nw > 150 && nh > 100) {
                WinMove nx, ny, nw, nh, "ahk_id " hwnd
                WinGetPos , , &gw, &gh, "ahk_id " hwnd
                if (Abs(gw - nw) > 4 || Abs(gh - nh) > 4) {
                    ; Storm guard for resizes: the app is rescaling behind our back.
                    FileAppend Format("{1} storm-guard {2}: resize answered {3}x{4} for {5}x{6}, aborting live resize`n", A_Now, WinGetProcessName("ahk_id " hwnd), gw, gh, nw, nh), A_Temp "\altdrag.log"
                    KeyWait btn
                    WinMove , , nw, nh, "ahk_id " hwnd
                    Watchdog(hwnd, nw, nh)
                    return
                }
            }
        }
        Sleep 8
    }
    ; Crossing to a monitor with another DPI (main 150 %, vertical 125 %) makes the
    ; app rescale itself, usually huge. Put the pre-drag physical size back.
    if (mode = "move") {
        if ghost
            ghost.Destroy()
        MouseGetPos &cx, &cy
        if (topZone && MonAt(cx, cy) = mon0) {
            WinMaximize "ahk_id " hwnd
            return
        }
        if (MonAt(cx, cy) = mon0) {
            if unstable {
                ; Outline-finished drag on the same monitor: place once, like a jump.
                WinGetPos , , &cw0, &ch0, "ahk_id " hwnd
                WinMove cx - (mx - wx), cy - (my - wy), , , "ahk_id " hwnd
                Loop 40 {
                    Sleep 5
                    WinGetPos , , &nw, &nh, "ahk_id " hwnd
                    if (nw != cw0 || nh != ch0)
                        break
                }
                Sleep 15
                WinMove , , ww, wh, "ahk_id " hwnd
                Watchdog(hwnd, ww, wh)
                return
            }
            ; Same monitor: the size must be exactly what we dragged; if the app
            ; rescaled itself on the way (seen once after a restore), fix it once.
            WinGetPos , , &ew, &eh, "ahk_id " hwnd
            if (ew != ww || eh != wh) {
                WinMove , , ww, wh, "ahk_id " hwnd
                FileAppend Format("{1} release-fix {2}: {3}x{4} -> {5}x{6}{7}`n", A_Now, WinGetProcessName("ahk_id " hwnd), ew, eh, ww, wh, fromMax ? " (from maximised)" : ""), A_Temp "\altdrag.log"
                Watchdog(hwnd, ww, wh)
            }
        }
        if (MonAt(cx, cy) != mon0) {
            ; Measured 2026-09-15: ONE WinMove across the boundary makes the app rescale
            ; once (x1.2 / x0.83) and then it is stable; one WinMove of the size by
            ; handle afterwards sticks. GlazeWM picks the new monitor up by itself.
            ; Never `glazewm command size` here: it acts on the *focused* window,
            ; which after a monitor change was another one (Zen/Terminal got resized).
            WinMove cx - (mx - wx), cy - (my - wy), , , "ahk_id " hwnd
            ; The rescale lands 125-156 ms after the move (measured x6); poll for it
            ; instead of sleeping a fixed 400 ms, then put the size back once.
            Loop 60 {
                Sleep 5
                WinGetPos , , &nw, &nh, "ahk_id " hwnd
                if (nw != ww || nh != wh)
                    break
            }
            Sleep 15
            WinMove , , ww, wh, "ahk_id " hwnd
            if topZone {
                Sleep 100
                WinMaximize "ahk_id " hwnd
            } else
                Watchdog(hwnd, ww, wh)
        }
    }
}
!LButton:: AltDrag("move")
!RButton:: AltDrag("resize")
