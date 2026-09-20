# The Command Palette (Hyper+Space) builds its app list when it starts and does
# not notice Start Menu shortcuts created later: an app installed after it
# started is simply not searchable. Killing it is enough -- it comes back on the
# next Win+Alt+Space, with a fresh list.
#   powershell -ExecutionPolicy Bypass -File restart-launcher.ps1
Get-Process Microsoft.CmdPal.UI -EA SilentlyContinue | Stop-Process -Force
Start-Sleep 2
Start-Process "explorer.exe" "shell:AppsFolder\Microsoft.CommandPalette_8wekyb3d8bbwe!App"
Start-Sleep 4
Get-Process Microsoft.CmdPal.UI -EA SilentlyContinue |
  Select-Object Id, StartTime | Format-Table -AutoSize | Out-String
