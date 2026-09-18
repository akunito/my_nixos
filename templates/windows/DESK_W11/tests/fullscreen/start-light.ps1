$d = "$env:TEMP\perf"
Get-CimInstance Win32_Process | ? { $_.CommandLine -match "aion-sampler|glazewm-events" } | % { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 1
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $d -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$d\aion-sampler.ps1`""
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $d -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$d\glazewm-events.ps1`""
