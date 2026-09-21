; Hyper+<letter> = Sway's app-toggle.sh, on Windows (AutoHotkey v2).
; Same decision table as user/wm/sway/scripts/app-toggle.sh:
;
;   no window                 -> launch, then follow the new window
;   one window, focused       -> hide it          (sway: move scratchpad)
;   one window, not focused   -> show it
;   2+ windows, one focused   -> cycle to the next one
;
; "Hide" is minimise here, and minimise is this desktop's scratchpad: showing a
; minimised window brings it to the workspace you are ON (sway's `scratchpad
; show`), while a window merely parked on another workspace takes you TO IT
; (sway's `focus`), which is what Diego asked for: "no quiero que Zen venga a
; mi, sino yo ir a donde Zen esta".
;
; Needs lib-glaze.ahk and lib-window-state.ahk. ASCII only, no BOM.
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\lib-glaze.ahk
#Include %A_LineFile%\..\lib-window-state.ahk
#Include %A_LineFile%\..\lib-workspaces.ahk
#Include %A_LineFile%\..\lib-layout-journal.ahk

AppToggle(spec, cmd) {
    t0 := A_TickCount
    ; Fast path first: hiding the window in front of you needs no state from
    ; GlazeWM at all, and a query costs ~200 ms. Sway's script runs in
    ; milliseconds; this one should feel the same.
    if (hwnd := AppFocusedRawWindow(spec)) {
        if (AppRawCount(spec) = 1) {
            Dbg("toggle " spec " hide (no query)")
            WinMinimize "ahk_id " hwnd
            Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
            return
        }
    }
    snap := GlazeSnapshot()
    if (!snap["ok"]) {
        ; GlazeWM did not answer. Doing nothing is the only safe move: an empty
        ; window list looks like "not running" and would start a second copy.
        Dbg("toggle " spec ": GlazeWM did not answer, doing nothing")
        return
    }
    wins := AppWindowsIn(snap["wins"], spec)
    if (!wins.Length) {
        ; Cloaked by the app itself = it went to the tray. Nothing outside the
        ; app can uncloak that window; re-running it is its own way back.
        if (hwnd := AppTrayWindow(spec)) {
            Dbg("toggle " spec " is in the tray, re-running it")
            try Run cmd
            Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
            return
        }
        ; A window GlazeWM does not manage (ignored by rule, odd popups).
        if (hwnd := AppRawWindow(spec)) {
            Dbg("toggle " spec " unmanaged window, activating it")
            if (WinGetMinMax("ahk_id " hwnd) = -1)
                WinRestore "ahk_id " hwnd
            WinActivate "ahk_id " hwnd
            Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
            return
        }
        AppLaunch(spec, cmd)
        Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
        return
    }

    focused := 0
    for i, w in wins
        if (AppIsFocused(w)) {
            focused := i
            break
        }

    if (focused && wins.Length = 1) {
        Dbg("toggle " spec " hide")
        WinMinimize "ahk_id " wins[1]["hwnd"]
        Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
        return
    }
    if (focused) {
        next := wins[Mod(focused, wins.Length) + 1]
        Dbg("toggle " spec " cycle " focused "/" wins.Length)
        AppShow(next, snap)
        Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
        return
    }
    Dbg("toggle " spec " show")
    AppShow(AppPreferred(wins), snap)
    Dbg("toggle " spec " done in " (A_TickCount - t0) " ms")
}

; Which of several windows to show: the hidden one first, like app-toggle.sh
; (a minimised window is this desktop's scratchpad, so it wins).
AppPreferred(wins) {
    for w in wins
        if (w["state"] = "minimized")
            return w
    for w in wins
        if (w["display"] = "hidden")
            return w
    return wins[1]
}

AppShow(w, snap := 0) {
    if (!snap)
        snap := GlazeSnapshot()
    if (w["state"] = "minimized") {
        ; Bring it to where you are: the workspace displayed on the monitor
        ; under the POINTER, like Sway's `scratchpad show` on the focused
        ; output. Taking the focused window's workspace instead sent it to the
        ; other monitor whenever something there still held the focus.
        cur := CurrentWs(CursorGroup(), snap["wss"])
        if (cur != "" && cur != w["ws"])
            GlazeOn(w["id"], "move --workspace " cur)
        WinRestore "ahk_id " w["hwnd"]
        Sleep 120                       ; let GlazeWM see the restore
    }
    ; Focus through GlazeWM, never WinActivate: a window parked on a hidden
    ; workspace is DWM-cloaked and Windows cannot activate it -- that is how
    ; Telegram got trapped behind a fullscreen game. GlazeWM switches to its
    ; workspace and uncloaks it.
    Glaze("focus --container-id " w["id"])
    ; Everything on the workspace of a fullscreen window is kept under it, or
    ; the game loses its direct path to the screen. Asking for a window by its
    ; own key is an explicit "show me this one", so lift it over the game --
    ; the opposite of an app that merely starts while you are playing. Decided
    ; from the snapshot taken before the focus: no second query, no wait.
    game := AppFullscreenIn(snap["wins"], w["ws"])
    if (game && game != w["hwnd"]) {
        Sleep 200
        Dbg("toggle: lifting the window over the fullscreen one")
        DllCall("SetWindowPos", "Ptr", w["hwnd"], "Ptr", 0,
            "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x3)   ; HWND_TOP, NOSIZE|NOMOVE
    }
}

; The handle of the fullscreen window on a workspace, or 0.
AppFullscreenIn(wins, ws) {
    if (ws = "")
        return 0
    for w in wins
        if (w["ws"] = ws && w["state"] = "fullscreen")
            return w["hwnd"]
    return 0
}
AppFullscreenOn(ws) => AppFullscreenIn(GlazeWins(), ws)

AppLaunch(spec, cmd) {
    static pending := Map()
    if (pending.Has(spec) && A_TickCount - pending[spec] < 5000) {
        Dbg("toggle " spec " debounced (launch in flight)")
        return
    }
    pending[spec] := A_TickCount
    ; An app launched while a fullscreen window has the focus must NOT take the
    ; screen: it opens behind the game, on the workspace you are on, and you
    ; decide when to go and see it (minimise or move the game).
    game := AppFullscreenFg()
    Dbg("toggle " spec " launch" (game ? " (behind the fullscreen window " game ")" : ""))
    try {
        Run cmd
    } catch as e {
        Dbg("toggle " spec " launch failed: " e.Message)
        return
    }
    w := AppWaitForWindow(spec, 15000)
    if (!w) {
        Dbg("toggle " spec " launched but no window appeared")
        return
    }
    if (!game) {
        ; It opens where you are pointing: the workspace displayed on the
        ; monitor under the cursor, with the size it had there last time (a
        ; size from another monitor means nothing -- different scale, different
        ; shape). Then follow it, since a rule could still have placed it
        ; elsewhere.
        AppPlaceNewWindow(spec, w)
        if (w["id"] != "")
            Glaze("focus --container-id " w["id"])
        else
            WinActivate "ahk_id " w["hwnd"]
        return
    }
    ; Windows hands the foreground to a freshly started app, which drops the
    ; game out of its direct path to the screen. Put the new window under the
    ; game and give the game the foreground back: it stays on the workspace
    ; you are on, and you decide when to go and see it.
    DllCall("SetWindowPos", "Ptr", w["hwnd"], "Ptr", game,
        "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)   ; NOSIZE|NOMOVE|NOACTIVATE
    WinActivate "ahk_id " game
}

; The window to wait for may be one GlazeWM does not manage (dialog-like apps
; are ignored by rule), so fall back to the raw window instead of blocking for
; the whole timeout.
; A freshly launched window belongs on the monitor you are pointing at, with
; whatever geometry the journal remembers for it THERE.
AppPlaceNewWindow(spec, w) {
    if (w["id"] = "")
        return
    cur := CurrentWs(CursorGroup())
    if (cur != "" && w["ws"] != "" && w["ws"] != cur) {
        Dbg("toggle " spec ": new window on " w["ws"] ", moving to " cur)
        GlazeOn(w["id"], "move --workspace " cur)
        Sleep 200
    }
    if (w["state"] = "tiling")           ; the layout owns its size
        return
    place := JournalPlacement(JournalRead(), JournalKey(w["proc"], w["class"]), CursorDevice())
    if !place
        return
    Dbg(Format("toggle {1}: restoring {2},{3} {4}x{5}{6}", spec, place["x"], place["y"],
        place["w"], place["h"], place["exact"] ? "" : " (scaled)"))
    GlazeOn(w["id"], Format("position --x-pos {1} --y-pos {2}", place["x"], place["y"]))
    Sleep 150
    GlazeOn(w["id"], Format("size --width {1}px --height {2}px", place["w"], place["h"]))
}

AppWaitForWindow(spec, timeoutMs) {
    start := A_TickCount, deadline := start + timeoutMs
    while (A_TickCount < deadline) {
        Sleep 250
        wins := AppWindows(spec)
        if (wins.Length)
            return wins[1]
        ; Give GlazeWM a moment first: a window it does manage shows up in the
        ; raw list before it is managed, and the id is what lets us follow it.
        if (A_TickCount - start > 3000 && (hwnd := AppRawWindow(spec)))
            return Map("id", "", "hwnd", hwnd, "state", "", "display", "", "ws", "")
    }
    return 0
}

; The focused window's handle when it is fullscreen, else 0.
AppFullscreenFg() {
    j := GlazeQuery("focused")
    if (!InStr(j, '"state":{"type":"fullscreen"'))
        return 0
    return RegExMatch(j, '"handle":(-?\d+)', &m) ? m[1] + 0 : 0
}

; Focused for our purposes = GlazeWM says so AND Windows agrees AND you can
; actually see it. A window behind a fullscreen game is "active" for Windows
; while being invisible, and minimising apps like Telegram there sends them to
; the tray, where their window is unrecoverable.
AppIsFocused(w) =>
    w["focus"] && w["state"] != "minimized"
        && WinActive("ahk_id " w["hwnd"]) && IsOnScreen(w["hwnd"])

; --- matching ---------------------------------------------------------------
; "telegram.exe" / "telegram"  -> process name
; "title:^Element"             -> title regex   (sway's title: prefix)
; "class:CabinetWClass"        -> window class regex
AppMatch(w, spec) {
    if (SubStr(spec, 1, 6) = "title:")
        return RegExMatch(w["title"], "i)" SubStr(spec, 7)) > 0
    if (SubStr(spec, 1, 6) = "class:")
        return RegExMatch(w["class"], "i)" SubStr(spec, 7)) > 0
    return StrLower(w["proc"]) = StrLower(RegExReplace(spec, "i)\.exe$"))
}

AppWindows(spec) => AppWindowsIn(GlazeWins(), spec)

AppWindowsIn(wins, spec) {
    out := []
    for w in wins
        if (AppMatch(w, spec))
            out.Push(w)
    return out
}

; The window of this app that is focused AND really on screen, straight from
; Win32 -- the fast path, taken before any query. A window behind a fullscreen
; game is "active" for Windows while being invisible, and minimising apps like
; Telegram there sends them to the tray, where their window is unrecoverable.
AppFocusedRawWindow(spec) {
    DetectHiddenWindows true
    fg := WinExist("A")
    if (!fg || !IsOnScreen(fg))
        return 0
    return AppMatchRaw(fg, spec) ? fg : 0
}

AppRawCount(spec) {
    DetectHiddenWindows true
    n := 0
    for hwnd in WinGetList() {
        if (!DllCall("IsWindowVisible", "Ptr", hwnd) || Cloaked(hwnd))
            continue
        if (DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr"))     ; owned popup
            continue
        if AppMatchRaw(hwnd, spec)
            n++
    }
    return n
}

AppMatchRaw(hwnd, spec) {
    try {
        if (SubStr(spec, 1, 6) = "title:")
            return RegExMatch(WinGetTitle("ahk_id " hwnd), "i)" SubStr(spec, 7)) > 0
        if (SubStr(spec, 1, 6) = "class:")
            return RegExMatch(WinGetClass("ahk_id " hwnd), "i)" SubStr(spec, 7)) > 0
        return StrLower(ExeOf(hwnd)) = StrLower(AppSpecExe(spec))
    }
    return false
}

AppSpecExe(spec) =>
    (SubStr(spec, 1, 6) = "title:" || SubStr(spec, 1, 6) = "class:") ? ""
        : (RegExMatch(spec, "i)\.exe$") ? spec : spec ".exe")

AppTrayWindow(spec) {
    DetectHiddenWindows true
    if !(exe := AppSpecExe(spec))
        return 0
    for hwnd in WinGetList("ahk_exe " exe)
        if (Cloaked(hwnd) & 1)          ; 1 = cloaked by the app itself
            return hwnd
    return 0
}

AppRawWindow(spec) {
    DetectHiddenWindows true
    if !(exe := AppSpecExe(spec))
        return 0
    for hwnd in WinGetList("ahk_exe " exe)
        if (DllCall("IsWindowVisible", "Ptr", hwnd) && !Cloaked(hwnd)
            && (WinGetStyle("ahk_id " hwnd) & 0xC00000))     ; has a caption
            return hwnd
    return 0
}
