# Kill (needs elevation for a uiAccess process) and relaunch through explorer so
# the new instance runs as the normal user, not elevated.
Get-Process AutoHotkey64_UIA -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 2
& explorer.exe "C:\Users\diego\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\hyper-desktops.lnk"
Start-Sleep 4
Get-Process AutoHotkey64_UIA | Select Id, StartTime | Format-Table | Out-String
