# Aion 2 after being dragged out and maximized again: a maximized window that
# still covers the whole monitor. The taskbar must stay below it after a
# workspace switch too.
$env:WSTEST_MAXFULL = "1"; & "$env:TEMP\perf\ws-hide-test.ps1"
