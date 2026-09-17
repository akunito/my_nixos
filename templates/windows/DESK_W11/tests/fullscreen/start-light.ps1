$d = "$env:TEMP\perf"
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $d -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$d\aion-sampler.ps1`""
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $d -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$d\glazewm-events.ps1`""
