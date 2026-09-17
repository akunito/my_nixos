. "$env:TEMP\perf\win32.ps1"
$ids = (Get-Process zebar -EA SilentlyContinue).Id
$h = [W]::GetTopWindow([IntPtr]::Zero); $out = @()
while ($h -ne [IntPtr]::Zero) { if ($ids -contains [W]::Pid($h) -and [W]::Cls($h) -eq "Tauri Window") { $r = [W]::Rect($h); $out += "visible=$([W]::IsWindowVisible($h)) [$($r.L),$($r.T) $($r.Rt-$r.L)x$($r.B-$r.T)]" }; $h = [W]::GetWindow($h, 2) }
"zebar pids=$($ids -join ',') pills: $($out -join ' | ')"
