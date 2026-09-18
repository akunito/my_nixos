# Like a real game: the window is classified fullscreen by GlazeWM itself (no
# set-fullscreen), so it has no previous state — that is the case where the
# taskbar was not marked again after coming back from another workspace.
$env:WSTEST_GAMELIKE = "1"; & "$env:TEMP\perf\ws-hide-test.ps1"
