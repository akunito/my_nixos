# Starts the Aion 2 trace: sampler + GlazeWM event stream + PresentMon (UAC once).
$d = "$env:TEMP\perf"; Set-Location $d
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'aion-sampler\.ps1|glazewm-events' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item "$d\sampler.log", "$d\glazewm-events.log", "$d\presentmon.csv" -ErrorAction SilentlyContinue
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $d -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$d\aion-sampler.ps1`""
Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $d -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$d\glazewm-events.ps1`""
Start-Process "$d\PresentMon.exe" -Verb RunAs -WorkingDirectory $d -WindowStyle Minimized -ArgumentList "--process_name AION2.exe --output_file `"$d\presentmon.csv`" --date_time --v2_metrics --terminate_on_proc_exit --stop_existing_session --session_name AionTrace"
New-Item -ItemType File -Force "$env:TEMP\hyper-debug.on" | Out-Null
"started $(Get-Date -Format HH:mm:ss)"
