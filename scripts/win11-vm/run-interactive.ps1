# Run a program in Diego's interactive desktop session (ssh / guest-exec land in session 0, invisible).
# usage: run-interactive.ps1 -Exe "C:\path\app.exe" [-Args "..."] [-WorkDir "C:\dir"]
# Principal must be COMPUTERNAME\user: USERDOMAIN is WORKGROUP and does not resolve (0x80070534, measured 2026-10-16).
param([Parameter(Mandatory)][string]$Exe, [string]$Args = "", [string]$WorkDir = "", [string]$User = $env:USERNAME)
$ErrorActionPreference = 'Continue'
$name = 'ClaudeInteractive'
schtasks /Delete /TN $name /F 2>$null | Out-Null
$wd = if ($WorkDir) { $WorkDir } else { Split-Path $Exe }
$a = if ($Args) { New-ScheduledTaskAction -Execute $Exe -Argument $Args -WorkingDirectory $wd } else { New-ScheduledTaskAction -Execute $Exe -WorkingDirectory $wd }
$p = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$User" -LogonType Interactive -RunLevel Highest
try { Register-ScheduledTask -TaskName $name -Action $a -Principal $p -Force | Out-Null; Start-ScheduledTask -TaskName $name; Start-Sleep 3; "started: " + (Get-ScheduledTask -TaskName $name).State } catch { "ERROR: " + $_.Exception.Message }
