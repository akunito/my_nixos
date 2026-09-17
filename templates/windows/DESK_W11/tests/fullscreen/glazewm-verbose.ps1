# Restart GlazeWM with verbose logging into %TEMP%\perf\glazewm-verbose.log (normal user, same config).
$exe = "C:\Program Files\glzr.io\GlazeWM\glazewm.exe"
$env:GLAZEWM_CONFIG_PATH = (Get-ItemProperty HKCU:\Environment).GLAZEWM_CONFIG_PATH
& "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe" command wm-exit 2>$null | Out-Null
Start-Sleep 3
Set-Location "C:\Program Files\glzr.io\GlazeWM"
Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c `"`"$exe`" start --verbose > `"$env:TEMP\perf\glazewm-verbose.log`" 2>&1`""
Start-Sleep 4
Get-Process glazewm | Select Id, StartTime
