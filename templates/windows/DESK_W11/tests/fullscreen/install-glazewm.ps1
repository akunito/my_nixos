# Replace the running GlazeWM with the fork MSI (uninstall first, then install).
$msi = "$env:TEMP\perf\glazewm-fix.msi"
& "C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe" command wm-exit 2>$null | Out-Null
Start-Sleep 3
Get-Process glazewm, glazewm-watcher, zebar -EA SilentlyContinue | Stop-Process -Force
$p = Get-CimInstance Win32_Product -Filter "Name like '%GlazeWM%'" -EA SilentlyContinue
foreach ($x in $p) { "uninstalling $($x.Name) $($x.Version) $($x.IdentifyingNumber)"; Start-Process msiexec.exe -Wait -ArgumentList "/x", $x.IdentifyingNumber, "/qn", "/norestart" }
Start-Sleep 2
$log = "$env:TEMP\perf\msi-install.log"
Start-Process msiexec.exe -Wait -ArgumentList "/i", "`"$msi`"", "/qn", "/norestart", "/l*v", "`"$log`""
"installed: $((Get-Item 'C:\Program Files\glzr.io\GlazeWM\glazewm.exe' -EA SilentlyContinue).VersionInfo.FileVersion)"
Get-ChildItem "C:\Program Files\glzr.io\GlazeWM" -EA SilentlyContinue | Select-Object -ExpandProperty Name
