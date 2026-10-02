# A UAC prompt asked for from a window that is not in front comes to the
# front by itself (AkuWM 0.2.7, ElevationPromptRaiser) instead of staying a
# shield on the other monitor's taskbar.
#
# PERSON-ASSISTED: the secure desktop cannot be driven. Answer the prompt
# (No is fine, the elevated command does nothing) when it appears. Not part of
# `all` for that reason.
Add-Type -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint f, bool i, uint a);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
'@ -Name D -Namespace W
$perf = "$env:TEMP\perf"
if (Get-Process consent -EA SilentlyContinue) { "FAIL a prompt was already pending before the case started (answer it and run again)"; exit 1 }
Remove-Item "$perf\uac-request.out", "$perf\uac-request.asked" -EA SilentlyContinue
# An application of ANOTHER process in front, as when a person is working.
# With the bare desktop in front (which is what the suite's reset leaves)
# Windows raises the prompt itself and the case passed on a daemon that did
# nothing (2026-10-02, first run on the signed 0.2.7: 3/3 and no line in the log).
$front = Start-Process charmap.exe -PassThru
$inFront = $false
foreach ($i in 1..40) {
  Start-Sleep -Milliseconds 150
  $fgPid = 0; [W.D]::GetWindowThreadProcessId([W.D]::GetForegroundWindow(), [ref]$fgPid) | Out-Null
  if ($fgPid -eq $front.Id) { $inFront = $true; break }
}
if (-not $inFront) { "FAIL the application meant to be in front never got the foreground; the case proves nothing"; Stop-Process -Id $front.Id -Force -EA SilentlyContinue; exit 1 }
$log = "$env:LOCALAPPDATA\akuwm\logs\akuwm.log"
$logFrom = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
$probe = Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $perf\uac-request-hwnd.ps1 -Delay 2 -Stay 60" -PassThru
$t0 = Get-Date; $asked = $null; $secureAt = $null; $answered = $false
while (((Get-Date) - $t0).TotalSeconds -lt 70) {
  if (-not $asked -and (Test-Path "$perf\uac-request.asked")) { $asked = Get-Date }
  if ($asked -and -not $secureAt -and [W.D]::OpenInputDesktop(0, $false, 1) -eq [IntPtr]::Zero) { $secureAt = ((Get-Date) - $asked).TotalMilliseconds }
  if ($asked -and (Test-Path "$perf\uac-request.out")) { $answered = $true; break }
  # Parked for good: no point in waiting the whole minute for a person who cannot see it.
  if ($asked -and -not $secureAt -and ((Get-Date) - $asked).TotalSeconds -gt 8) { break }
  Start-Sleep -Milliseconds 50
}
if (-not $asked) { "FAIL the probe never asked for elevation"; exit 1 }
$line = Get-Content "$perf\uac-request.asked" -EA SilentlyContinue
# In front at that moment: a window of some other application -- not the
# probe's, and not the bare desktop (the pointer may have handed the focus to
# whatever it rests on; any real application counts).
$fgPid = 0; $fgClass = New-Object System.Text.StringBuilder 256
if ($line -match 'hwnd=(0x[0-9a-f]+) fg=(0x[0-9a-f]+)') {
  $fg = [IntPtr][Convert]::ToInt64($Matches[2], 16)
  [W.D]::GetWindowThreadProcessId($fg, [ref]$fgPid) | Out-Null; [W.D]::GetClassName($fg, $fgClass, 256) | Out-Null
}
$fgName = (Get-Process -Id $fgPid -EA SilentlyContinue).ProcessName
if ($fgPid -ne 0 -and $fgPid -ne $probe.Id -and "$fgClass" -notin 'Progman', 'WorkerW') { "PASS the request came from a window that was not in front ($fgName had the foreground)" }
else { "FAIL the foreground was the probe or the bare desktop when the request was made, the case proves nothing: $line [$fgClass]" }
if ($secureAt) { "PASS the prompt came to the front by itself, {0:N0} ms after the request" -f $secureAt }
else { "FAIL the prompt stayed parked on the taskbar (no secure desktop in 8 s)" }
# And it was the daemon: its own line, written after this case started.
$raised = $false
if ((Test-Path $log) -and (Get-Item $log).Length -gt $logFrom) {
  $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); [void]$fs.Seek($logFrom, 'Begin')
  $raised = (New-Object IO.StreamReader $fs).ReadToEnd() -match 'elevation prompt 0x[0-9a-f]+ was parked on the taskbar: raised'; $fs.Close()
}
if ($raised) { "PASS the daemon says it raised a parked prompt" } else { "FAIL no 'elevation prompt ... raised' line in the daemon log: the daemon did not do it" }
if ($answered) {
  Start-Sleep -Milliseconds 800
  if (Get-Process consent -EA SilentlyContinue) { "FAIL a prompt is still pending after the answer" } else { "PASS nothing is left pending once it is answered" }
} elseif ($secureAt) { "FAIL the prompt was not answered within a minute (person-assisted case)" }
Stop-Process -Id $front.Id -Force -EA SilentlyContinue
# The probe's own window goes with its process; a parked prompt outlives it, so say so.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object CommandLine -match 'uac-request-hwnd' | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
if (Get-Process consent -EA SilentlyContinue) { "NOTE a prompt is still parked on the primary monitor's taskbar: click the shield and answer it" }
