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
#Include lib-window-state.ahk
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
Glaze(args) {
    t := A_TickCount
    RunWait('"' glazeExe '" command ' args, , "Hide")
    Dbg(Format("glaze {1} ({2} ms)", args, A_TickCount - t))
}
; ---- Debug trace (opt-in): %TEMP%\hyper-debug.on present -> every gesture and
; every GlazeWM command is appended to %TEMP%\altdrag.log with timings. Power
; and display-change events are logged always (cheap, and they explain the
; resume-from-sleep glitches); a display change also dumps GlazeWM's monitor
; map to %TEMP%\glaze-monitors-<time>.json two seconds later.
Dbg(msg) {
    if FileExist(A_Temp "\hyper-debug.on")
        FileAppend A_Now " " msg "`n", A_Temp "\altdrag.log"
}
OnMessage(0x218, (wp, lp, *) => (wp = 0x12 || wp = 7 || wp = 4) ? FileAppend(A_Now " power " (wp = 4 ? "suspend" : "resume(" wp ")") " monitors=" MonitorGetCount() "`n", A_Temp "\altdrag.log") : 0)
OnMessage(0x7E, (wp, lp, *) => (FileAppend(A_Now " displaychange " (lp & 0xFFFF) "x" (lp >> 16) " bpp=" wp " monitors=" MonitorGetCount() "`n", A_Temp "\altdrag.log"), SetTimer(DumpGlazeMonitors, -2000)))
DumpGlazeMonitors() {
    try FileAppend GlazeQuery("monitors"), A_Temp "\glaze-monitors-" A_Now ".json", "UTF-8"
}
; Window events (debug only): focus changes, maximise/restore/minimise, size
; changes outside our gestures (a size storm shows up here with its own
; timing) and DWM cloak/uncloak (what GlazeWM does to hide a window).
MonName(hwnd) => DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr") = PrimaryMon() ? "main" : "vertical"
; Z-order of the visible top-level windows, top first ("*" marks the focused
; one), for diagnosing re-stacking: GlazeWM re-applies z-order on focus, so a
; click on one window can move several. Owned, cloaked, caption-less and
; shell/bar windows are skipped; first 12 only.
ZOrderLine(focusHwnd) {
    DetectHiddenWindows true
    buf := Buffer(4, 0)
    zlist := []
    h := DllCall("GetTopWindow", "Ptr", 0, "Ptr")
    while (h && zlist.Length < 12) {
        cur := h
        h := DllCall("GetWindow", "Ptr", cur, "UInt", 2, "Ptr")          ; GW_HWNDNEXT
        try {
            if (!DllCall("IsWindowVisible", "Ptr", cur)
                || !(WinGetStyle("ahk_id " cur) & 0xC00000)              ; no caption
                || DllCall("GetWindow", "Ptr", cur, "UInt", 4, "Ptr"))   ; GW_OWNER: owned
                continue
            NumPut("UInt", 0, buf)
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", cur, "UInt", 14, "Ptr", buf, "UInt", 4)
            if NumGet(buf, 0, "UInt")                                    ; DWMWA_CLOAKED
                continue
            zexe := WinGetProcessName("ahk_id " cur)
            if (zexe = "AutoHotkey64_UIA.exe" || zexe = "zebar.exe")
                continue
            if (zexe = "explorer.exe") {
                zcls := WinGetClass("ahk_id " cur)
                if (zcls = "Progman" || zcls = "WorkerW" || zcls = "Shell_TrayWnd")
                    continue
            }
            zlist.Push(StrReplace(zexe, ".exe") "(" cur ")" (cur = focusHwnd ? "*" : ""))
        } catch
            continue
    }
    zline := ""
    for zi, ztxt in zlist
        zline .= (zi > 1 ? " > " : "") ztxt
    return zline
}
; ---- Zebar pills vs fullscreen windows -----------------------------------
; A visible always-on-top window over a fullscreen game costs it the direct
; path to the screen: DWM composes the frame instead (PresentMon "Composed:
; Flip" = 45 fps and +60 ms on Aion 2, measured 2026-09-17). A pill is hidden
; whenever the focused window covers it completely -- only a window spanning
; the whole monitor does, since the pills sit over the taskbar strip that a
; maximised window never reaches.
PillSync(*) {
    static last := 0, recheck := 0
    if (A_TickCount - last < 200) {        ; location changes arrive in bursts
        if (!recheck)                      ; but the last one still has to be seen
            recheck := 1, SetTimer(() => (recheck := 0, PillSync()), -600)
        return
    }
    last := A_TickCount
    DetectHiddenWindows true
    for pill in WinGetList("ahk_class Tauri Window ahk_exe zebar.exe") {
        try {
            WinGetPos &px, &py, &pw, &ph, "ahk_id " pill
            if (pw < 100 || ph > 100)            ; zebar's own utility window
                continue
            mon := MonitorAt(px + pw // 2, py + ph // 2)
            covered := MonitorIsCovered(mon, pill)
            DetectHiddenWindows true          ; MonitorIsCovered turns it off, and
            shown := DllCall("IsWindowVisible", "Ptr", pill)   ; WinShow needs it
            if (covered && shown)
                WinHide("ahk_id " pill), Dbg("pill hidden (monitor " mon.i " covered)")
            else if (!covered && !shown)
                WinShow("ahk_id " pill), Dbg("pill shown (monitor " mon.i ")")
        }
    }
}

MonitorAt(x, y) {
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return {i: A_Index, l: l, t: t, r: r, b: b}
    }
    MonitorGet(1, &l, &t, &r, &b)
    return {i: 1, l: l, t: t, r: r, b: b}
}

; Is some window covering this whole monitor (a game, a video at full screen)?
; The pill is checked against the monitor, not against the focused window: with
; the focus on the other monitor the pill would otherwise pop back over a game.
MonitorIsCovered(mon, pill) {
    DetectHiddenWindows false
    for hwnd in WinGetList() {
        if (hwnd = pill)
            continue
        try {
            exe := WinGetProcessName("ahk_id " hwnd)
            if (exe = "zebar.exe" || exe = "explorer.exe")   ; the taskbar covers the pill too
                continue
            if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
                continue
            if (WinGetMinMax("ahk_id " hwnd) = -1)           ; minimised
                continue
            ; A window parked on a hidden workspace is DWM-cloaked, and AHK still
            ; lists it: without this the pill stayed hidden on empty workspaces
            ; once a game had been open on that monitor.
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
            if (cloaked)
                continue
            WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
            if (wx <= mon.l && wy <= mon.t && wx + ww >= mon.r && wy + wh >= mon.b)
                return true
        }
    }
    return false
}

WinEvCb(hook, ev, hwnd, idObj, idChild, thread, time) {
    global altDragExp
    static state := Map()
    if (idObj != 0 || idChild != 0 || !hwnd)
        return
    ; Foreground changes, and size changes of the foreground window (a game
    ; usually grows to fullscreen after it is already focused).
    ; Foreground changes, size changes (a game grows to fullscreen after it has
    ; focus) and cloak/uncloak (workspace switches).
    if (ev = 0x3 || ev = 0x800B || ev = 0x8017 || ev = 0x8018)
        PillSync()
    if !FileExist(A_Temp "\hyper-debug.on")
        return
    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)   ; top-level only
        return
    DetectHiddenWindows true
    try {
        exe := WinGetProcessName("ahk_id " hwnd)
        if (exe = "AutoHotkey64_UIA.exe" || exe = "zebar.exe" || WinGetClass("ahk_id " hwnd) = "tooltips_class32")
            return
        if (ev = 0x3) {
            Dbg(Format("focus -> {1} '{2}' hwnd {3} {4}", exe, SubStr(WinGetTitle("ahk_id " hwnd), 1, 40), hwnd, MonName(hwnd)))
            Dbg("zorder now: " ZOrderLine(hwnd))
            SetTimer(() => Dbg("zorder +150ms: " ZOrderLine(hwnd)), -150)   ; after GlazeWM reacts
            return
        }
        if (ev = 0x8017 || ev = 0x8018) {
            Dbg(Format("{1} {2} hwnd {3} {4}", ev = 0x8017 ? "cloaked" : "uncloaked", exe, hwnd, MonName(hwnd)))
            return
        }
        if !(WinGetStyle("ahk_id " hwnd) & 0xC00000)   ; no caption: dropdowns, menus, previews
            return
        mm := WinGetMinMax("ahk_id " hwnd)
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    } catch
        return
    prev := state.Has(hwnd) ? state[hwnd] : ""
    state[hwnd] := {mm: mm, w: w, h: h}
    if (prev = "")
        return
    if (prev.mm != mm)
        Dbg(Format("state {1} hwnd {2}: {3} -> {4} ({5}x{6}) {7}", exe, hwnd, StateName(prev.mm), StateName(mm), w, h, MonName(hwnd)))
    else if ((prev.w != w || prev.h != h) && altDragExp = "")
        Dbg(Format("size {1} hwnd {2}: {3}x{4} -> {5}x{6} at {7},{8} {9} (outside gesture)", exe, hwnd, prev.w, prev.h, w, h, x, y, MonName(hwnd)))
}
StateName(mm) => mm = 1 ? "maximised" : mm = -1 ? "minimised" : "normal"
winEvPtr := CallbackCreate(WinEvCb, , 7)
PillSync()                                  ; get the pills right on start/reload

winEvHooks := [DllCall("SetWinEventHook", "UInt", 0x3, "UInt", 0x3, "Ptr", 0, "Ptr", winEvPtr, "UInt", 0, "UInt", 0, "UInt", 0x2, "Ptr")
             , DllCall("SetWinEventHook", "UInt", 0x800B, "UInt", 0x800B, "Ptr", 0, "Ptr", winEvPtr, "UInt", 0, "UInt", 0, "UInt", 0x2, "Ptr")
             , DllCall("SetWinEventHook", "UInt", 0x8017, "UInt", 0x8018, "Ptr", 0, "Ptr", winEvPtr, "UInt", 0, "UInt", 0, "UInt", 0x2, "Ptr")]
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
    Dbg("switcher open")
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
^!#Escape:: {
    Dbg("close " WinGetProcessName("A"))
    WinClose "A"
}
^!#f:: {
    h := WinGetID("A")
    Dbg("hyper+f " WinGetProcessName(h) ": " (WinGetMinMax(h) = 1 ? "restore" : "maximise"))
    WinGetMinMax(h) = 1 ? WinRestore(h) : WinMaximize(h)
}
^!#Space:: Send "#!{Space}" ; PowerToys Command Palette (its own hotkey is Win+Alt+Space; PowerToys Run is disabled) — rofi stand-in

; raise-or-launch — the app-toggle.sh idea: focus if running, minimise if focused, launch otherwise
; Hyper+<letter>: go to the app, don't bring it here. A window parked on a hidden
; workspace is DWM-cloaked and `WinActivate` cannot show it (it only lights up in
; the taskbar and stays unreachable -- that is how Telegram got trapped behind a
; fullscreen game), so GlazeWM is asked to focus it instead: it switches to the
; window's workspace and uncloaks it. Launching a new app leaves it where you are.
Toggle(exe, cmd) {
    DetectHiddenWindows true
    hwnd := WinExist("ahk_exe " exe)
    Dbg("toggle " exe " " (hwnd ? (WinActive("ahk_id " hwnd) ? "minimise" : "focus") : "launch"))
    if !hwnd {
        Run cmd
        return
    }
    ; Minimise only a window you can actually see. A window sitting behind a
    ; fullscreen game still counts as "active" for Windows, and minimising apps
    ; like Telegram sends them to the tray, where they cloak their own window:
    ; nothing outside the app can bring that back (lost window, 2026-09-18).
    if (WinActive("ahk_id " hwnd) && IsOnScreen(hwnd)) {
        WinMinimize "ahk_id " hwnd
        return
    }
    if (Cloaked(hwnd) & 1) {           ; hidden by the app itself (tray)
        Dbg("toggle " exe " is in the tray, re-running it")
        Run cmd                        ; its own activation path is the only way
        return
    }
    if (id := GlazeIdOf(hwnd))
        Glaze("focus --container-id " id)
    else
        WinActivate "ahk_id " hwnd      ; not managed (ignored windows, popups)
}



; GlazeWM's container id for a window handle, or "" if it doesn't manage it.
GlazeIdOf(hwnd) {
    j := GlazeQuery("windows"), pos := 1
    while pos := RegExMatch(j, '"type":"window","id":"([^"]+)"[\s\S]*?"handle":(\d+)', &m, pos) {
        if (m[2] + 0 = hwnd + 0)
            return m[1]
        pos += StrLen(m[0])
    }
    return ""
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
; Runs on a timer, NOT in the hotkey thread: measured 2026-09-15, the blocking
; version kept the hotkey busy up to 4.5 s and AutoHotkey dropped the next
; Alt+drag (4 presses lost in 35 s). A new gesture cancels it. A small answer
; (< 8 %: Windows Terminal snapping to its cell grid, 1 px) is accepted, not fought.
SmallDelta(w, h, ww, wh) => Abs(w - ww) * 12 < ww && Abs(h - wh) * 12 < wh
wdTick := ""
WatchdogStop() {
    global wdTick
    if wdTick
        SetTimer wdTick, 0
    wdTick := ""
}
Watchdog(hwnd, ww, wh) {
    global wdTick
    WatchdogStop()
    fixes := 0, n := 0
    tick() {
        global wdTick
        n++
        DetectHiddenWindows true
        try {
            if (WinGetMinMax("ahk_id " hwnd) = 0) {
                WinGetPos , , &w, &h, "ahk_id " hwnd
                if (w != ww || h != wh) {
                    if SmallDelta(w, h, ww, wh) {
                        Dbg(Format("watchdog {1}: accepted {2}x{3} for {4}x{5} (grid snap)", WinGetProcessName("ahk_id " hwnd), w, h, ww, wh))
                        n := 999
                    } else if (++fixes > 3) {
                        FileAppend Format("{1} watchdog {2}: giving up at {3}x{4}`n", A_Now, WinGetProcessName("ahk_id " hwnd), w, h), A_Temp "\altdrag.log"
                        n := 999
                    } else {
                        WinMove , , ww, wh, "ahk_id " hwnd
                        FileAppend Format("{1} watchdog {2}: {3}x{4} -> {5}x{6} (fix {7})`n", A_Now, WinGetProcessName("ahk_id " hwnd), w, h, ww, wh, fixes), A_Temp "\altdrag.log"
                    }
                }
            }
        } catch
            n := 999
        if (n >= 75) {
            SetTimer tick, 0
            if (wdTick = tick)
                wdTick := ""
        }
    }
    wdTick := tick
    SetTimer tick, 20
}
; The window under the cursor can vanish mid-gesture (a tooltip, a tab-drag
; preview, an app closing): every Win* call then throws TargetError. Catch it
; here, drop the outline and log, instead of AutoHotkey's error dialog.
; Measured 2026-09-15: a window GlazeWM parks on a non-displayed workspace is
; cloaked (DWMWA_CLOAKED = 2) and AutoHotkey then reports it as not found unless
; DetectHiddenWindows is on. That is what killed a drag right after resume from
; sleep (main monitor still off): Discord was cloaked 5 ms after the placement
; WinMove. With DetectHiddenWindows on the gesture finishes on the hidden window.
altDragGhost := "", altDragHwnd := 0, altDragT0 := 0, altDragExp := "", altDragPhase := ""
AltDrag(mode) {
    global altDragGhost, altDragHwnd, altDragT0, altDragExp, altDragPhase
    if altDragPhase {
        ; A second Alt+button while the previous gesture is still running (its
        ; post-release placement or watchdog): AutoHotkey would otherwise drop it
        ; silently (#MaxThreadsPerHotkey). Logged to measure how often it happens.
        FileAppend Format("{1} dropped {2}: previous gesture still in phase '{3}' ({4} ms after it started)`n", A_Now, mode, altDragPhase, A_TickCount - altDragT0), A_Temp "\altdrag.log"
        return
    }
    altDragPhase := "prep", altDragT0 := A_TickCount, altDragExp := ""
    try AltDragCore(mode)
    catch TargetError as e {
        if altDragGhost
            try altDragGhost.Destroy()
        altDragGhost := ""
        DetectHiddenWindows true
        what := (altDragHwnd && WinExist("ahk_id " altDragHwnd)) ? "still exists, hidden" : "destroyed"
        FileAppend Format("{1} target-lost ({2}) hwnd {3} {4}: {5}`n", A_Now, mode, altDragHwnd, what, e.Message), A_Temp "\altdrag.log"
        return
    }
    if altDragExp {   ; a gesture actually ran: final state, after any watchdog
        DetectHiddenWindows true
        try {
            WinGetPos &fx, &fy, &fw, &fh, "ahk_id " altDragHwnd
            MouseGetPos &cx, &cy
            mm := DllCall("MonitorFromPoint", "Int64", (cy << 32) | (cx & 0xFFFFFFFF), "UInt", 2, "Ptr")
            mw := DllCall("MonitorFromWindow", "Ptr", altDragHwnd, "UInt", 2, "Ptr")
            Dbg(Format("gesture-end {1} {2}: final {3},{4} {5}x{6} expected {7} minmax={8} win-on-cursor-monitor={9} {10} ms", mode, WinGetProcessName("ahk_id " altDragHwnd), fx, fy, fw, fh, altDragExp, WinGetMinMax("ahk_id " altDragHwnd), mm = mw ? "yes" : "NO", A_TickCount - altDragT0))
        }
    }
    altDragExp := "", altDragPhase := ""
}
AltDragCore(mode) {
    global altDragGhost, altDragHwnd, altDragExp, altDragT0, altDragPhase
    MouseGetPos &mx, &my, &hwnd
    if !hwnd {
        Dbg("ignored " mode ": no window under the cursor at " mx "," my)
        return
    }
    altDragHwnd := hwnd
    WatchdogStop()
    DetectHiddenWindows true
    cls := WinGetClass("ahk_id " hwnd)
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd") {
        Dbg("ignored " mode ": desktop/taskbar (" cls ")")
        return
    }
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    if (ww < 200 || wh < 80) {
        ; A tooltip or tab-drag preview sits under the cursor (Vivaldi's is 237x39,
        ; seen 2026-09-15: the watchdog then forced that size onto the real window).
        ; Drag its owner instead, or leave it alone.
        owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")
        if !owner {
            Dbg(Format("ignored {1}: tiny window {2} '{3}' {4}x{5} with no owner", mode, WinGetProcessName("ahk_id " hwnd), cls, ww, wh))
            return
        }
        Dbg(Format("tiny window {1} {2}x{3} -> dragging its owner", cls, ww, wh))
        hwnd := owner
        WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    }
    ; Measured 2026-09-15: WinActivate costs 110 ms even when the window is
    ; already active (and its fallback flashed the focus to the desktop);
    ; SetForegroundWindow is 0 ms from a hook hotkey. Fall back only if it fails.
    tAct := A_TickCount
    if !WinActive("ahk_id " hwnd) {
        DllCall("SetForegroundWindow", "Ptr", hwnd)
        if !WinActive("ahk_id " hwnd) {
            ; Another app holds the foreground lock: attach to its input thread
            ; for the call (measured 0 ms, works), WinActivate only as last resort.
            fg := DllCall("GetForegroundWindow", "Ptr"), me := DllCall("GetCurrentThreadId", "UInt")
            ft := fg ? DllCall("GetWindowThreadProcessId", "Ptr", fg, "Ptr", 0, "UInt") : 0
            if (ft && ft != me)
                DllCall("AttachThreadInput", "UInt", ft, "UInt", me, "Int", 1), DllCall("SetForegroundWindow", "Ptr", hwnd), DllCall("AttachThreadInput", "UInt", ft, "UInt", me, "Int", 0)
            if !WinActive("ahk_id " hwnd)
                WinActivate "ahk_id " hwnd
        }
    }
    tAct := A_TickCount - tAct
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
        ; Measured 2026-09-15: forcing an 80 % box whenever one side did not fit
        ; made the size drift on every maximise/restore across monitors
        ; (1668x2160 -> 3072x1694 -> 1382x2424). Fit each side on its own.
        if (nw < 200 || nh < 150)
            nw := Round((ar - al) * 0.8), nh := Round((ab - at) * 0.8)
        else
            nw := Min(nw, ar - al), nh := Min(nh, ab - at)
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
    altDragExp := mode = "resize" ? "(resize)" : ww "x" wh
    Dbg(Format("gesture-start {1} {2} hwnd {3} at {4},{5} {6}x{7}{8} cursor {9},{10} monitor={11} prep {12} ms (activate {13} ms)", mode, WinGetProcessName("ahk_id " hwnd), hwnd, wx, wy, ww, wh, fromMax ? " (from maximised)" : "", mx, my, mon0 = PrimaryMon() ? "main" : "vertical", A_TickCount - altDragT0, tAct))
    MonAt(px, py) => DllCall("MonitorFromPoint", "Int64", (py << 32) | (px & 0xFFFFFFFF), "UInt", 2, "Ptr")
    ghost := "", topZone := false, unstable := false, outlined := "", clamped := false, snapped := false
    ; The side of the origin monitor that faces the other monitor. Measured
    ; 2026-09-15 (7 of 7 storms): a per-monitor-DPI window whose edge enters the
    ; virtual gap between the monitors (3840..4608 here) gets its DPI re-evaluated
    ; by Windows and rescales (x1.2 height, up to x1.74 width) although the cursor
    ; never left the monitor. Live moves and resizes stop at that edge; crossing
    ; is what the outline + one jump on release are for.
    ; GetMonitorInfo on the handle itself: MonitorFromPoint on a monitor's own
    ; top-left corner answered the OTHER monitor here (measured), so no points.
    ; (edgeL/edgeR: AutoHotkey names are case-insensitive, so a capitalised
    ; variant was the same variable as the MonitorGet loops' lower-case one, and
    ; WorkAreaAt clobbered it every tick — measured 2026-09-15.)
    mi := Buffer(40, 0), NumPut("UInt", 40, mi)
    DllCall("GetMonitorInfo", "Ptr", mon0, "Ptr", mi)
    edgeL := NumGet(mi, 4, "Int"), edgeR := NumGet(mi, 12, "Int"), onMain := (mon0 = PrimaryMon())
    EdgeClampX(x, w) => onMain ? Min(x, edgeR - w) : Max(x, edgeL)
    Dbg(Format("edges {1}: live moves keep x {2} {3}", onMain ? "main" : "vertical", onMain ? "<=" : ">=", onMain ? edgeR " - width" : edgeL))
    altDragPhase := "drag"
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
                altDragGhost := ghost := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")   ; click-through, layered; -DPIScale = raw pixels (measured: default is x1.5)
                ghost.BackColor := "c4a7e7"
                WinSetTransparent 90, ghost
            }
            ; Top zone (<= 6 px under the top of the work area): the outline becomes
            ; the whole work area and the release maximises there (sway/Windows snap).
            topZone := WorkAreaAt(cx, cy, &al, &at, &ar, &ab) && (cy - at) <= 6
            if topZone {
                if (outlined != "top-zone")
                    Dbg(Format("outline top-zone: cursor {1},{2} {3} ms into the gesture", cx, cy, A_TickCount - altDragT0)), outlined := "top-zone"
                ghost.Show("NA x" al " y" at " w" (ar - al) " h" (ab - at))
            } else if (MonAt(cx, cy) = mon0 && !unstable) {
                ghost.Hide()
                nx := EdgeClampX(wx + dx, ww)
                if (nx != wx + dx && !clamped)
                    Dbg(Format("edge-clamp {1}: kept x {2} {3} (window would be at {4})", WinGetProcessName("ahk_id " hwnd), onMain ? "<=" : ">=", onMain ? edgeR - ww : edgeL, wx + dx)), clamped := true
                WinMove nx, wy + dy, , , "ahk_id " hwnd
                ; Storm guard: if the app answered a plain move with a rescale (stale
                ; DPI context, seen on the vertical monitor), stop touching it and
                ; finish the drag as an outline; placement happens once on release.
                WinGetPos , , &gw, &gh, "ahk_id " hwnd
                if (gw != ww || gh != wh) {
                    if SmallDelta(gw, gh, ww, wh) {
                        ; The app snapped to its own grid (Windows Terminal: 1 px per
                        ; move, measured): that is its answer, adopt it. Real storms
                        ; are +19 % to +73 % (log 2026-09-15).
                        if !snapped
                            Dbg(Format("grid-snap {1}: {2}x{3} -> {4}x{5} adopted (further 1-px flips not logged)", WinGetProcessName("ahk_id " hwnd), ww, wh, gw, gh)), snapped := true
                        ww := gw, wh := gh, altDragExp := ww "x" wh
                    } else {
                        unstable := true
                        FileAppend Format("{1} storm-guard {2}: rescaled to {3}x{4} during move (expected {5}x{6})`n", A_Now, WinGetProcessName("ahk_id " hwnd), gw, gh, ww, wh), A_Temp "\altdrag.log"
                    }
                }
            } else {
                if (outlined != (unstable ? "storm" : "other-monitor"))
                    Dbg(Format("outline {1}: cursor {2},{3} {4} ms into the gesture", unstable ? "storm" : "other-monitor", cx, cy, A_TickCount - altDragT0)), outlined := unstable ? "storm" : "other-monitor"
                ghost.Show("NA x" (cx - (mx - wx)) " y" (cy - (my - wy)) " w" ww " h" wh)
            }
        } else {
            nx := left ? wx + dx : wx
            ny := top ? wy + dy : wy
            nw := left ? ww - dx : ww + dx
            nh := top ? wh - dy : wh + dy
            if onMain
                nw := Min(nw, edgeR - nx)               ; right edge stays off the gap
            else if (left && nx < edgeL)
                nw := nw - (edgeL - nx), nx := edgeL    ; left edge stays off the gap
            if (nw > 150 && nh > 100) {
                WinMove nx, ny, nw, nh, "ahk_id " hwnd
                WinGetPos , , &gw, &gh, "ahk_id " hwnd
                if ((Abs(gw - nw) > 4 || Abs(gh - nh) > 4) && !SmallDelta(gw, gh, nw, nh)) {
                    ; Storm guard for resizes: the app is rescaling behind our back
                    ; (a grid snap of a few cells is not that: keep resizing live).
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
    altDragPhase := "release"
    ; Crossing to a monitor with another DPI (main 150 %, vertical 125 %) makes the
    ; app rescale itself, usually huge. Put the pre-drag physical size back.
    if (mode = "move") {
        if ghost
            ghost.Destroy(), altDragGhost := ""
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
#MaxThreadsPerHotkey 2   ; so a press during a running gesture reaches AltDrag (which logs and drops it)
!LButton:: AltDrag("move")
!RButton:: AltDrag("resize")
#MaxThreadsPerHotkey 1
