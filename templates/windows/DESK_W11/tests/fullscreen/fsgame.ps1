# Reproduces the Aion 2 case: a window created slightly larger than the monitor
# that settles to exactly the monitor rect must stay in GlazeWM's fullscreen
# state (otherwise MarkFullscreenWindow never runs and the taskbar stays above).
# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"
ParkCursorOnPrimary
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($mon.children | ? isDisplayed).name | Out-Null
Start-Sleep 1
$p = StartAsUser "$d\fliptest.exe" "16 0 gamelike"
Start-Sleep 5
$w = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest" | Sort-Object width -Descending)[0]
"state=$($w.state.type) rect=$($w.x),$($w.y) $($w.width)x$($w.height) monitor=$($mon.width)x$($mon.height)"
Remove-Item "$d\fsgame.csv" -EA SilentlyContinue
& "$d\PresentMon.exe" --process_name fliptest.exe --output_file "$d\fsgame.csv" --v2_metrics --timed 5 --terminate_after_timed --stop_existing_session --session_name AkuGame --no_console_stats *> $null
(Import-Csv "$d\fsgame.csv" | Group-Object PresentMode | % { "$($_.Name)=$($_.Count)" }) -join ", "
