# Elevated fliptest + non-elevated cloak attempt through the shell.
. "$env:TEMP\perf\win32.ps1"
$d = "$env:TEMP\perf"
$p = Start-Process "$d\fliptest.exe" -ArgumentList "20 0" -PassThru -Verb RunAs
Start-Sleep 3
$h = [IntPtr]::Zero; $x = [W]::GetTopWindow([IntPtr]::Zero)
while ($x -ne [IntPtr]::Zero) { if ([W]::Cls($x) -eq "FlipTestWnd") { $h = $x; break }; $x = [W]::GetWindow($x, 2) }
"target hwnd=$h (elevated fliptest)"
& "$d\cloaktest.exe" $([int64]$h) 1
Start-Sleep 1
"visible=$([W]::IsWindowVisible($h)) cloaked=$([W]::Cloak($h))"
& "$d\cloaktest.exe" $([int64]$h) 0
Stop-Process -Id $p.Id -Force -EA SilentlyContinue
