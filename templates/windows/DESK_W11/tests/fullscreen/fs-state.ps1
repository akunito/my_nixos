# Does GlazeWM classify a window that opens borderless-fullscreen as fullscreen,
# and does the Zebar pill hide itself while it is focused?
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"; # The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$p = Start-Process "$d\fliptest.exe" -ArgumentList "12 0 now" -PassThru
Start-Sleep 4
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.processName -eq "fliptest" }
"glazewm: state=$($w.state.type) display=$($w.displayState) rect=$($w.x),$($w.y) $($w.width)x$($w.height)"
& $glaze command --id $w.id set-fullscreen "--maximized=false" | Out-Null
Start-Sleep 2
$w2 = (& $glaze query windows | ConvertFrom-Json).data.windows | ? { $_.processName -eq "fliptest" }
"after set-fullscreen: state=$($w2.state.type)"
& "$d\pill-state.ps1"
Start-Sleep 5
& "$d\pill-state.ps1"
