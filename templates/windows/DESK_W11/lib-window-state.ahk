; Shared window-state helpers (hyper-desktops.ahk and tests/fullscreen).
; Whether a window is really on screen decides if Hyper+<letter> may minimise it:
; a window behind a fullscreen game is "active" for Windows but invisible, and
; minimising apps like Telegram sends them to the tray, where they cloak their
; own window and nothing outside the app can bring it back.
Cloaked(hwnd) {
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Int*", &cloaked, "UInt", 4)
    return cloaked
}
; Visible to the user right now: not hidden, not cloaked by the app or by
; GlazeWM (another workspace), not minimised.
IsOnScreen(hwnd) =>
    DllCall("IsWindowVisible", "Ptr", hwnd) && !Cloaked(hwnd)
        && WinGetMinMax("ahk_id " hwnd) != -1
