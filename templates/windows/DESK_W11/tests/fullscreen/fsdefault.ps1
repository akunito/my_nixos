# The window manager's CLI: AkuWM's shim once the desk has been switched to
# it (akuwm-switch.ps1 writes the marker), GlazeWM's otherwise. Inline rather
# than in a library because each of these runs on its own, copied alone into
# %TEMP%\perf and sometimes by the elevated daemon.
$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$wmMarker = "$env:LOCALAPPDATA\akuwm\wm-cli.txt"
if (Test-Path $wmMarker) { $wmCli = (Get-Content $wmMarker -Raw).Trim(); if ($wmCli -and (Test-Path $wmCli)) { $glaze = $wmCli } }
$p = Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList "12 0" -PassThru
Start-Sleep 3
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest"
& $glaze command --id $w.id set-fullscreen | Out-Null
Start-Sleep 2
$w2 = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest"
"state=$($w2.state.type) json=$($w2.state | ConvertTo-Json -Compress)"
