$glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
$p = Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList "10 0 now" -PassThru
Start-Sleep 3
$w = (& $glaze query windows | ConvertFrom-Json).data.windows | ? processName -eq "fliptest"
"state=$($w.state.type) maximized=$($w.state.maximized) shownOnTop=$($w.state.shownOnTop) rect=$($w.x),$($w.y) $($w.width)x$($w.height)"
