$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$p = Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList "12 0" -PassThru
Start-Sleep 3
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest"
& $glaze command --id $w.id set-fullscreen | Out-Null
Start-Sleep 2
$w2 = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest"
"state=$($w2.state.type) json=$($w2.state | ConvertTo-Json -Compress)"
