# Elevated capture daemon (one UAC prompt): for every <name>.req file (content = seconds)
# runs a timed PresentMon capture of fliptest.exe/AION2.exe into <name>.csv, then <name>.done.
$d = "$env:TEMP\perf"; Set-Location $d
"daemon $(Get-Date -Format HH:mm:ss)" | Set-Content "$d\cap-daemon.alive"
while ($true) {
  foreach ($req in Get-ChildItem "$d\*.req" -EA SilentlyContinue) {
    $n = $req.BaseName; $secs = [int](Get-Content $req.FullName -Raw); Remove-Item $req.FullName
    Remove-Item "$d\$n.csv","$d\$n.done" -EA SilentlyContinue
    & "$d\PresentMon.exe" --process_name fliptest.exe --process_name AION2.exe --output_file "$d\$n.csv" --date_time --v2_metrics --timed $secs --terminate_after_timed --stop_existing_session --session_name AkuCap --no_console_stats 2>&1 | Out-File "$d\$n.pmlog"
    "done" | Set-Content "$d\$n.done"
  }
  # <name>.elev = "<script.ps1 in this folder> [args]" -> run elevated, output in <name>.out
  foreach ($req in Get-ChildItem "$d\*.elev" -EA SilentlyContinue) {
    $n = $req.BaseName; $line = (Get-Content $req.FullName -Raw).Trim(); Remove-Item $req.FullName
    $script, $rest = $line -split ' ', 2
    if ($script -notmatch '^[\w-]+\.ps1$') { "rejected" | Set-Content "$d\$n.out"; continue }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$d\$script' $rest" *>&1 | Out-File -Encoding utf8 "$d\$n.out.tmp"
    Move-Item -Force "$d\$n.out.tmp" "$d\$n.out"
  }
  if (Test-Path "$d\cap-daemon.stop") { Remove-Item "$d\cap-daemon.stop"; break }
  Start-Sleep -Milliseconds 200
}
