# Restarts ShareX when its private memory passes a cap. Run every 30 min by the scheduled task "ShareX watchdog" (bootstrap.ps1).
# WHY: ShareX 21.0.0 never frees its captures: 90 captures over 3 days left it at 3.1 GB private (~35 MB each, one
# full-monitor bitmap), and that commit pushed DESK_W11 to 37 MB free RAM while AION 2 loaded (measured 2026-10-12).
# Suspect: the main window's ThumbnailView keeps every task; not confirmed.
param([int]$MaxMB = 1500)
$p = Get-Process ShareX -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p -or $p.PrivateMemorySize64 / 1MB -lt $MaxMB) { return }
# Don't kill it mid-task: a capture/upload writes the log, a recording runs ffmpeg as a child.
$log = Get-ChildItem "$env:USERPROFILE\Documents\ShareX\Logs\*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
if ($log -and ((Get-Date) - $log.LastWriteTime).TotalSeconds -lt 120) { return }
if (Get-CimInstance Win32_Process -Filter "Name='ffmpeg.exe' AND ParentProcessId=$($p.Id)") { return }
$exe = $p.Path
Stop-Process -Id $p.Id -Force
$p.WaitForExit(10000) | Out-Null
Start-Process $exe -ArgumentList '-silent'
