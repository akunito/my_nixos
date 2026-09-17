# Does GlazeWM classify a window that opens borderless-fullscreen as fullscreen,
# and does the Zebar pill hide itself while it is focused?
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"; $glaze = "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"
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
