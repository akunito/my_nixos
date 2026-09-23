# Minimises every visible elevated top-level window (the Administrator
# console): the focus policy refuses the attach and the injection while an
# elevated window has the foreground, and a build without uiAccess cannot
# even see it. Runs elevated through the capture daemon's mailbox.
# `park-elevated.ps1 restore` brings back what the last park minimised
# (handles kept in parkelev.list), shown without activation so the suite's
# last focus is not undone; a suite that ends without it leaves the console
# hidden in the taskbar, which is what happened after every run until now.
param([string]$Mode = "park")
$list = "$env:TEMP\perf\parkelev.list"
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class E {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(P cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, uint pid);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("advapi32.dll")] public static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
  [DllImport("advapi32.dll")] public static extern bool GetTokenInformation(IntPtr t, int c, out uint info, uint len, out uint ret);
}
"@
function Elevated($pid2) {
  $p = [E]::OpenProcess(0x1000, $false, $pid2); if ($p -eq [IntPtr]::Zero) { return $false }
  $t = [IntPtr]::Zero; $ok = [E]::OpenProcessToken($p, 8, [ref]$t); [void][E]::CloseHandle($p)
  if (-not $ok) { return $false }
  $info = [uint32]0; $ret = [uint32]0; $r = [E]::GetTokenInformation($t, 20, [ref]$info, 4, [ref]$ret); [void][E]::CloseHandle($t)
  return ($r -and $info -ne 0)
}
if ($Mode -eq "restore") {
  $restored = 0
  if (Test-Path $list) {
    foreach ($h in (Get-Content $list | ? { $_ -match '^\d+$' })) {
      $hwnd = [IntPtr][int64]$h
      if ([E]::IsIconic($hwnd)) { [void][E]::ShowWindow($hwnd, 4); $restored++ }
    }
    Remove-Item $list -EA SilentlyContinue
  }
  "restored $restored elevated window(s)"
  exit 0
}
$parked = 0
$kept = @()
[E]::EnumWindows({ param($h, $l)
  if ([E]::IsWindowVisible($h) -and -not [E]::IsIconic($h)) {
    $pid2 = 0; [E]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
    $t = New-Object System.Text.StringBuilder 256; [E]::GetWindowText($h, $t, 256) | Out-Null
    if ($t.Length -gt 0 -and $pid2 -ne $PID -and (Elevated $pid2)) {
      $name = (Get-Process -Id $pid2 -EA SilentlyContinue).ProcessName
      if ($name -notmatch '^(akuwm|cap|powershell_cap)$' -and $t.ToString() -notmatch 'cap-daemon') {
        [void][E]::ShowWindow($h, 6); $script:parked++; $script:kept += [int64]$h; "parked $h $name [$($t.ToString())]"
      }
    }
  }
  $true }, [IntPtr]::Zero) | Out-Null
if ($kept.Count -gt 0) { $kept | Set-Content $list }
"parked $parked elevated window(s)"
