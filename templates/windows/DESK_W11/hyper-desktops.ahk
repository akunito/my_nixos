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
;   Hyper+F             fullscreen toggle                     = fullscreen toggle
;   Hyper+Space         Start / PowerToys Run                 = rofi combi
;   Hyper+<letter>      raise-or-launch (lib-app-toggle.ahk)  = app-toggle.sh
;   Hyper+T / Hyper+R   terminal / second terminal            = kitty / Alacritty
;   Hyper+H/J/K/?       focus left / down / up / right        = focus <dir>
;   Hyper+Shift+J/K/L/: move the window in that direction     = window-move.sh
;   Hyper+Shift+U/P/I/O narrower / wider / taller / shorter   = resize
;   Hyper+Shift+F       floating toggle                       = floating toggle
;   Hyper+Shift+S       sticky toggle (all workspaces)        = sticky toggle
;   Hyper+Shift+- / -   hide the window / bring the last one back = scratchpad
;   Hyper+F5            put the layout back together (after a monitor nap)
;   Hyper+Shift+F5      fetch every other screen's windows here / send them back
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
; Coordinates here are PHYSICAL pixels, the window manager's own: lib-glaze.ahk
; puts this thread in PER_MONITOR_AWARE_V2 at load. Without that AHK is
; system-DPI aware and the vertical monitor reads 1.2x too big (see the note
; there, and tests/ahk-space.ahk, which measured the old space).
; v2 defaults Mouse coords to the active window's CLIENT area; WinGetPos/WinMove
; are screen coords. Mixing them made Alt+drag feed the window's own motion back
; into the delta (flicker/jumps). Everything below assumes screen coords.
CoordMode "Mouse", "Screen"
#SingleInstance Force
#Include lib-window-state.ahk
#Include lib-glaze.ahk
#Include lib-app-toggle.ahk
#Include lib-workspaces.ahk
#Include lib-tiling-drag.ahk
#Include lib-repair.ahk
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
; glazeExe, Glaze(), GlazeOn(), GlazeQuery() and Dbg() live in lib-glaze.ahk.
; Power and display-change events are logged always (cheap, and they explain
; the resume-from-sleep glitches); a display change also dumps GlazeWM's
; monitor map to %TEMP%\glaze-monitors-<time>.json two seconds later.
OnMessage(0x218, PowerEvent)
PowerEvent(wp, lp, *) {
    if !(wp = 0x12 || wp = 7 || wp = 4)
        return
    FileAppend A_Now " power " (wp = 4 ? "suspend" : "resume(" wp ")") " monitors=" MonitorGetCount() "`n", A_Temp "\altdrag.log"
    ; Write the layout down before the machine goes away: what comes back is
    ; not what left, and this is the last healthy state anyone will see.
    if (wp = 4)
        JournalSnapshot()
}
OnMessage(0x7E, (wp, lp, *) => (FileAppend(A_Now " displaychange " (lp & 0xFFFF) "x" (lp >> 16) " bpp=" wp " monitors=" MonitorGetCount() "`n", A_Temp "\altdrag.log"), SetTimer(DumpGlazeMonitors, -2000), SetTimer(RepairAfterDisplayChange, -6000)))
; Monitors arrive one at a time and GlazeWM needs a moment to settle, so the
; repair runs once, six seconds after the last change in a burst.
RepairAfterDisplayChange() {
    Dbg("repair: display change settled, " MonitorGetCount() " monitor(s)")
    RepairLayout(false)
    SetTimer(() => JournalSnapshot(), -8000)   ; record the repaired layout
}
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
            zexe := ExeOf(cur)
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
    ; Short throttle: the pill was visible over the game for up to half a second
    ; every time the game got the focus back, and those frames are composed.
    if (A_TickCount - last < 60) {         ; location changes arrive in bursts
        if (!recheck)                      ; but the last one still has to be seen
            recheck := 1, SetTimer(() => (recheck := 0, PillSync()), -250)
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
            ; Only when the trace is on: Dbg's argument is built before Dbg
            ; can check the marker, and MonitorCoveredBy walks every window a
            ; second time -- on every focus change.
            if FileExist(A_Temp "\hyper-debug.on")
                Dbg(Format("pill {1},{2} {3}x{4} -> monitor {5} [{6},{7} {8}x{9}] covered={10} by {11}",
                    px, py, pw, ph, mon.i, mon.l, mon.t, mon.r - mon.l, mon.b - mon.t,
                    covered, MonitorCoveredBy(mon, pill)))
            DetectHiddenWindows true          ; MonitorIsCovered turns it off, and
            shown := DllCall("IsWindowVisible", "Ptr", pill)   ; WinShow needs it
            if (covered && shown)
                WinHide("ahk_id " pill), Dbg("pill hidden (monitor " mon.i " covered)")
            else if (!covered && !shown)
                WinShow("ahk_id " pill), Dbg("pill shown (monitor " mon.i ")")
        }
    }
}


; Is some window covering this whole monitor (a game, a video at full screen)?
; The pill is checked against the monitor, not against the focused window: with
; the focus on the other monitor the pill would otherwise pop back over a game.
; Which window covers a monitor, for the trace.
MonitorCoveredBy(mon, pill) {
    DetectHiddenWindows false
    for hwnd in WinGetList() {
        if (hwnd = pill)
            continue
        try {
            exe := ExeOf(hwnd)
            if (exe = "zebar.exe" || exe = "explorer.exe")
                continue
            if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)
                continue
            if (WinGetMinMax("ahk_id " hwnd) = -1)
                continue
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
            if (cloaked)
                continue
            WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
            if (wx <= mon.l && wy <= mon.t && wx + ww >= mon.r && wy + wh >= mon.b)
                return exe " [" wx "," wy " " ww "x" wh "]"
        }
    }
    return "-"
}
MonitorIsCovered(mon, pill) {
    DetectHiddenWindows false
    for hwnd in WinGetList() {
        if (hwnd = pill)
            continue
        try {
            exe := ExeOf(hwnd)
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
        exe := ExeOf(hwnd)
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
; The journal: a snapshot every minute while things look healthy, and one now.
SetTimer(() => JournalSnapshot(), 60000)
SetTimer(() => JournalSnapshot(), -5000)

winEvHooks := [DllCall("SetWinEventHook", "UInt", 0x3, "UInt", 0x3, "Ptr", 0, "Ptr", winEvPtr, "UInt", 0, "UInt", 0, "UInt", 0x2, "Ptr")
             , DllCall("SetWinEventHook", "UInt", 0x800B, "UInt", 0x800B, "Ptr", 0, "Ptr", winEvPtr, "UInt", 0, "UInt", 0, "UInt", 0x2, "Ptr")
             , DllCall("SetWinEventHook", "UInt", 0x8017, "UInt", 0x8018, "Ptr", 0, "Ptr", winEvPtr, "UInt", 0, "UInt", 0, "UInt", 0x2, "Ptr")]
; PrimaryMon(), CursorGroup(), WindowGroup(), Ws(), CurrentWs() and WsCycle()
; live in lib-workspaces.ahk: the monitor under the POINTER is the one these
; keys act on, like Sway's focused output.
Loop 10 {
    k := Mod(A_Index, 10)
    Hotkey "^!#" k, ((n) => (*) => FocusWorkspace(Ws(n)))(k)
    Hotkey "^!#+" k, ((n) => (*) => Glaze("move --workspace " MoveWs(n)))(k)
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
    Dbg("close " ExeOf(WinExist("A")))
    WinClose "A"
}
; Put the desktop back together: workspaces to the monitor their number says,
; and every window to the geometry the journal saw it with on that monitor.
^!#F5:: {
    r := RepairLayout(true)
    TrayTip("Layout repaired", r["workspaces"] " workspace(s), " r["windows"] " window(s)")
}
; Something is on a screen that is dark: borrow every other monitor's windows
; onto this one, and press again to send them back where they were. A switched
; off monitor is not gone to Windows (it drops out for two seconds and is
; listed again, dark), so nothing automatic can know -- the person does.
^!#+F5:: {
    r := WmPipeAsk("compat command fetch-windows")
    TrayTip(InStr(r, '"fetched":true') ? "Windows fetched here" : "Windows sent back", "Hyper+Shift+F5 again to undo")
}
^!#f:: Glaze("toggle-fullscreen")             ; sway: fullscreen toggle
^!#+g:: Glaze("toggle-fullscreen")            ; sway: hyper+Shift+g, same thing
^!#Space:: Send "#!{Space}" ; PowerToys Command Palette (its own hotkey is Win+Alt+Space; PowerToys Run is disabled) — rofi stand-in

; ---- Tiling: the sway keymap ---------------------------------------------
; Windows tile by default (config.yaml `initial_state: tiling`), with sway's
; gaps and the same orientation rule (GlazeWM picks the tiling direction from
; the monitor shape, like sway's `default_orientation auto`, so the vertical
; monitor stacks windows).
;
;   focus      hyper+h / j / k / ?        left / down / up / right
;   move       hyper+Shift+j / k / l / :  left / down / up / right
;   resize     hyper+Shift+u / p / i / o  narrower / wider / taller / shorter
;   float      hyper+Shift+f, hyper+Shift+Space
;   sticky     hyper+Shift+s              shown on every workspace of its monitor
;   fullscreen hyper+f, hyper+Shift+g
;   hide/show  hyper+Shift+- / hyper+-    sway's scratchpad, minimise here
;   split      hyper+Shift+n              toggle tiling direction (no sway twin)
^!#h:: Glaze("focus --direction left")
^!#j:: Glaze("focus --direction down")
^!#k:: Glaze("focus --direction up")
^!#?:: Glaze("focus --direction right")       ; sway: hyper+question (hyper+l is Telegram)
^!#+j:: Glaze("move --direction left")
^!#+k:: Glaze("move --direction down")
^!#+l:: Glaze("move --direction up")
^!#+;:: Glaze("move --direction right")       ; sway: hyper+colon
^!#+u:: Glaze("resize --width -5%")           ; sway: resize shrink width 5 ppt
^!#+p:: Glaze("resize --width 5%")
^!#+i:: Glaze("resize --height 5%")
^!#+o:: Glaze("resize --height -5%")
^!#+f:: Glaze("toggle-floating --centered=false")
^!#+Space:: Glaze("toggle-floating --centered=false")
^!#+s:: Glaze("toggle-sticky")
^!#+n:: Glaze("toggle-tiling-direction")
; sway's scratchpad: hide the focused window, and bring back the last hidden one
; to the workspace you are on (AppShow does the move + restore + focus).
^!#+-:: Glaze("set-minimized")
^!#-:: {
    for w in GlazeWins()
        if (w["state"] = "minimized" && w["ws"] != "") {
            AppShow(w)
            return
        }
    Dbg("scratchpad show: nothing minimised")
}

; raise-or-launch = Sway's app-toggle.sh; the decision table and the reasons
; live in lib-app-toggle.ahk (AppToggle).
^!#t:: AppToggle("WindowsTerminal.exe", "wt.exe")           ; sway: kitty
^!#r:: AppToggle("alacritty.exe", A_ProgramFiles "\Alacritty\alacritty.exe")   ; sway: Alacritty
^!#z:: AppToggle("zen.exe", A_ProgramFiles "\Zen Browser\zen.exe")
^!#v:: AppToggle("vivaldi.exe", EnvGet("LOCALAPPDATA") "\Vivaldi\Application\vivaldi.exe")
^!#l:: AppToggle("Telegram.exe", A_AppData "\Telegram Desktop\Telegram.exe")
^!#d:: AppToggle("Obsidian.exe", EnvGet("LOCALAPPDATA") "\Programs\Obsidian\Obsidian.exe")
^!#c:: AppToggle("Code.exe", "code")
^!#p:: AppToggle("Bitwarden.exe", EnvGet("LOCALAPPDATA") "\Programs\Bitwarden\Bitwarden.exe")
^!#o:: AppToggle("Element.exe", EnvGet("LOCALAPPDATA") "\element-desktop\Element.exe")
^!#y:: AppToggle("Spotify.exe", A_AppData "\Spotify\Spotify.exe")
^!#x:: AppToggle("CalculatorApp.exe", "calc")
^!#e:: AppToggle("explorer.exe", "explorer")
^!#u:: AppToggle("dbeaver.exe", EnvGet("LOCALAPPDATA") "\DBeaver\dbeaver.exe")
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
                        Dbg(Format("watchdog {1}: accepted {2}x{3} for {4}x{5} (grid snap)", ExeOf(hwnd), w, h, ww, wh))
                        n := 999
                    } else if (++fixes > 3) {
                        FileAppend Format("{1} watchdog {2}: giving up at {3}x{4}`n", A_Now, ExeOf(hwnd), w, h), A_Temp "\altdrag.log"
                        n := 999
                    } else {
                        WinMove , , ww, wh, "ahk_id " hwnd
                        FileAppend Format("{1} watchdog {2}: {3}x{4} -> {5}x{6} (fix {7})`n", A_Now, ExeOf(hwnd), w, h, ww, wh, fixes), A_Temp "\altdrag.log"
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
            Dbg(Format("gesture-end {1} {2}: final {3},{4} {5}x{6} expected {7} minmax={8} win-on-cursor-monitor={9} {10} ms", mode, ExeOf(altDragHwnd), fx, fy, fw, fh, altDragExp, WinGetMinMax("ahk_id " altDragHwnd), mm = mw ? "yes" : "NO", A_TickCount - altDragT0))
        }
    }
    altDragExp := "", altDragPhase := ""
}
; TilingDrag() and TilingDropCommand() live in lib-tiling-drag.ahk.
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
            Dbg(Format("ignored {1}: tiny window {2} '{3}' {4}x{5} with no owner", mode, ExeOf(hwnd), cls, ww, wh))
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
    ; A TILED window is never dragged around by hand: GlazeWM turns a tiling
    ; window that something repositions into a floating one, and it loses its
    ; place in the layout. Outline the gesture instead and let GlazeWM do the
    ; move or the resize on release, which is what the same gesture does in
    ; sway (the layout reflows, the window stays tiled).
    tileId := GlazeTilingIdOf(hwnd)
    Dbg(Format("{1} target {2} hwnd {3}: {4}", mode, ExeOf(hwnd), hwnd,
        tileId ? "tiled, id " tileId : "not tiled"))
    if (tileId) {
        TilingDrag(mode, hwnd, tileId, mx, my, wx, wy, ww, wh)
        return
    }
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
        FileAppend Format("{1} max-restore {2}: normal={3}x{4} came-out={5}x{6} -> {7}x{8}`n", A_Now, ExeOf(hwnd), nw, nh, rw, rh, ww, wh), A_Temp "\altdrag.log"
    }
    if (mode = "resize") {
        left := (mx - wx) < (ww / 2), top := (my - wy) < (wh / 2)
    }
    btn := mode = "move" ? "LButton" : "RButton"
    SetWinDelay -1
    altDragExp := mode = "resize" ? "(resize)" : ww "x" wh
    startDevice := MonitorDeviceAt(mx, my)
    Dbg(Format("gesture-start {1} {2} hwnd {3} at {4},{5} {6}x{7}{8} cursor {9},{10} monitor={11} prep {12} ms (activate {13} ms)", mode, ExeOf(hwnd), hwnd, wx, wy, ww, wh, fromMax ? " (from maximised)" : "", mx, my, startDevice, A_TickCount - altDragT0, tAct))
    ghost := "", topZone := false, outlined := ""
    ; The window itself is the preview.
    ;
    ; It used to live-move only inside the monitor it started on, and cross as
    ; a translucent outline that jumped once on release. The reason was real:
    ; measured 2026-09-15, seven times out of seven, a window whose edge entered
    ; the gap between where this script thought a monitor was and where it
    ; physically started got its DPI re-evaluated and rescaled, up to x1.74,
    ; without the cursor ever leaving the monitor. That gap was this script
    ; being system-DPI aware. It has not existed since lib-glaze.ahk asked for
    ; PER_MONITOR_AWARE_V2, so the outline, the edge clamp and the storm guard
    ; are gone with it and the real window crosses.
    ;
    ; The hand keeps its place on the window: grabbed a third of the way along
    ; the title bar, still a third of the way along after the new screen
    ; resizes it. Every tick reads the size the window HAS -- Windows rescales
    ; it for the new DPI and AkuWM applies layout.across_monitors, both behind
    ; our back -- and puts that point back under the cursor. Nothing here needs
    ; to know either happened.
    fx := ww > 0 ? (mx - wx) / ww : 0.5
    fy := wh > 0 ? (my - wy) / wh : 0.5
    Dbg(Format("grab at {1}%, {2}% of the window", Round(fx * 100), Round(fy * 100)))
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
            if !ghost {
                altDragGhost := ghost := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x80000 -DPIScale")   ; click-through, layered; -DPIScale = raw pixels (measured: default is x1.5)
                ghost.BackColor := "c4a7e7"
                WinSetTransparent 90, ghost
            }
            ; Top zone (<= 6 px under the top of the work area): the outline becomes
            ; the whole work area and the release maximises there (sway/Windows snap).
            ; The only outline left, because it shows something the window is not.
            topZone := WorkAreaAt(cx, cy, &al, &at, &ar, &ab) && (cy - at) <= 6
            if topZone {
                if (outlined != "top-zone")
                    Dbg(Format("outline top-zone: cursor {1},{2} {3} ms into the gesture", cx, cy, A_TickCount - altDragT0)), outlined := "top-zone"
                ghost.Show("NA x" al " y" at " w" (ar - al) " h" (ab - at))
            } else {
                ghost.Hide()
                WinGetPos , , &gw, &gh, "ahk_id " hwnd
                if (gw != ww || gh != wh) {
                    Dbg(Format("resized under the drag: {1}x{2} -> {3}x{4}", ww, wh, gw, gh))
                    ww := gw, wh := gh, altDragExp := ww "x" wh
                }
                WinMove Round(cx - fx * ww), Round(cy - fy * wh), , , "ahk_id " hwnd
            }
        } else {
            nx := left ? wx + dx : wx
            ny := top ? wy + dy : wy
            nw := left ? ww - dx : ww + dx
            nh := top ? wh - dy : wh + dy
            ; No clamp to the monitor's edges. It was there to keep an edge
            ; out of the gap between where this script thought a screen was
            ; and where it physically started, and that gap went with the
            ; system-DPI awareness (2026-09-21). A window resized across the
            ; boundary is Windows' business, as it is for every other app.
            if (nw > 150 && nh > 100) {
                WinMove nx, ny, nw, nh, "ahk_id " hwnd
                WinGetPos , , &gw, &gh, "ahk_id " hwnd
                if ((Abs(gw - nw) > 4 || Abs(gh - nh) > 4) && !SmallDelta(gw, gh, nw, nh)) {
                    ; Storm guard for resizes: the app is rescaling behind our back
                    ; (a grid snap of a few cells is not that: keep resizing live).
                    FileAppend Format("{1} storm-guard {2}: resize answered {3}x{4} for {5}x{6}, aborting live resize`n", A_Now, ExeOf(hwnd), gw, gh, nw, nh), A_Temp "\altdrag.log"
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
    if (mode = "move") {
        if ghost
            ghost.Destroy(), altDragGhost := ""
        MouseGetPos &cx, &cy
        ; Nothing to place: the window has been where the cursor is for the
        ; whole gesture. Everything that used to live here -- the jump across
        ; the boundary, the poll for the DPI rescale, putting the pre-drag size
        ; back, the watchdog that kept putting it back -- existed to undo the
        ; damage of a crossing this script could not watch. It can now.
        if topZone {
            WinMaximize "ahk_id " hwnd
            return
        }
        ; It was maximised when the drag began and it has landed on ANOTHER
        ; screen: maximise it there. Diego chose that over arriving restored.
        ; Only across screens -- dragging a maximised window down on its own
        ; monitor is how everybody un-maximises one, and taking that away would
        ; be worse than the feature is worth.
        if (fromMax && MonitorDeviceAt(cx, cy) != startDevice) {
            Dbg("was maximised and crossed: maximising on the new screen")
            WinMaximize "ahk_id " hwnd
        }
    }
}

#MaxThreadsPerHotkey 2   ; so a press during a running gesture reaches AltDrag (which logs and drops it)
!LButton:: AltDrag("move")
!RButton:: AltDrag("resize")
#MaxThreadsPerHotkey 1
