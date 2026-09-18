# A window that opens MAXIMIZED (Age of Empires II DE) must stay maximized:
# floating would un-maximize it and clamp it 10px inside the workspace, and the
# game takes that size as its fullscreen resolution.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"
ParkCursorOnPrimary
Get-Process fliptest -EA SilentlyContinue | Stop-Process -Force
$mon = (& $glaze query monitors | ConvertFrom-Json).data.monitors | ? { $_.x -eq 0 -and $_.y -eq 0 }
& $glaze command focus --workspace ($mon.children | ? isDisplayed).name | Out-Null
Start-Sleep 1
$p = Start-Process "$d\fliptest.exe" -ArgumentList "10 0 startmax" -PassThru
Start-Sleep 4
$w = @((& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest" | Sort-Object width -Descending)[0]
$h = [IntPtr][int64]$w.handle
$r = [W]::Rect($h)
"state=$($w.state.type) maximized=$($w.state.maximized) glazeRect=$($w.x),$($w.y) $($w.width)x$($w.height) isZoomed=$([W]::IsZoomed($h)) monitor=$($mon.width)x$($mon.height)"
