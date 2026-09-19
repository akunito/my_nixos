# Bring the whole stack back up after installing a fork build: GlazeWM with the
# config from the dotfiles clone, Zebar, and the AHK script.
# GLAZEWM_CONFIG_PATH is a *user* environment variable, and a process started
# from WSL interop does not necessarily see it, so the path is passed explicitly.
$cfg = "C:\Users\diego\.dotfiles\templates\windows\DESK_W11\glazewm\config.yaml"
Get-Process glazewm, glazewm-watcher, zebar -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 2
Start-Process "C:\Program Files\glzr.io\GlazeWM\glazewm.exe" -ArgumentList "start", "--config", "`"$cfg`""
Start-Sleep 8
Start-Process "C:\Program Files\glzr.io\Zebar\zebar.exe"
Start-Sleep 3
# The running script is a uiAccess process: a normal user cannot kill it, but
# #SingleInstance Force makes the new instance take over.
Start-Process "C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe" `
  -ArgumentList "C:\Users\diego\.dotfiles\templates\windows\DESK_W11\hyper-desktops.ahk" `
  -WorkingDirectory "C:\Users\diego\.dotfiles\templates\windows\DESK_W11"
Start-Sleep 4
Get-Process glazewm, zebar, AutoHotkey64_UIA -EA SilentlyContinue |
  Select-Object Id, ProcessName | Format-Table -AutoSize | Out-String
