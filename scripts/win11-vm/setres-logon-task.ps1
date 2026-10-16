# Register the SetRes2560 logon task for the autologon user (run once over ssh as admin). The guest's display mode does
# not survive a reboot on its own (QXL/spice agent pick 2048x1080 or 4096 wide at boot, measured 2026-10-16), so
# setres.ps1 runs 15 s after sign-in; the viewer (view.sh, --auto-resize=never) never resizes it afterwards.
param([string]$User = "aku", [int]$W = 2560, [int]$H = 1440)
$a = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Users\Public\setres.ps1 $W $H" -WorkingDirectory "C:\Users\Public"
$t = New-ScheduledTaskTrigger -AtLogOn -User "$env:COMPUTERNAME\$User"; $t.Delay = "PT15S"
$p = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$User" -LogonType Interactive -RunLevel Limited
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
Register-ScheduledTask -TaskName "SetRes$W" -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
"registered SetRes$W for $User"
