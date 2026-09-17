$f = "$env:TEMP\perf\glazewm-events.log"
& 'C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe' sub -e all | ForEach-Object { [IO.File]::AppendAllText($f, (Get-Date -Format 'HH:mm:ss.fff') + ' ' + $_ + "`n") }
