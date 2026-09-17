# Aion 2 perf trace: window/overlay state every 500 ms (logged on change),
# CPU of the suspects every 2 s, GPU 3D per process every 6 s.
param([string]$Log = "$env:TEMP\perf\sampler.log", [string]$Game = "AION2")
$ErrorActionPreference = "Continue"
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint c);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
  public static string Cls(IntPtr h) { var s = new StringBuilder(128); GetClassName(h, s, 128); return s.ToString(); }
  public static string Txt(IntPtr h) { var s = new StringBuilder(128); GetWindowText(h, s, 128); return s.ToString(); }
  public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
  public static int Cloak(IntPtr h) { int v; DwmGetWindowAttribute(h, 14, out v, 4); return v; }
  public static R Rect(IntPtr h) { R r; GetWindowRect(h, out r); return r; }
}
"@
$names = @{}
function PName($procId) { if (-not $names.ContainsKey($procId)) { $p = Get-Process -Id $procId -ErrorAction SilentlyContinue; $names[$procId] = if ($p) { $p.ProcessName } else { "?" } }; $names[$procId] }
function L($m) { "$(Get-Date -Format 'HH:mm:ss.fff') $m" | Add-Content -Encoding utf8 $Log }
function RS($r) { "[$($r.L),$($r.T) $($r.Rt - $r.L)x$($r.B - $r.T)]" }

function GameWindow($procIds) {
  $h = [W]::GetTopWindow([IntPtr]::Zero); $best = [IntPtr]::Zero; $area = 0
  while ($h -ne [IntPtr]::Zero) {
    if ($procIds -contains [W]::Pid($h) -and [W]::IsWindowVisible($h)) {
      $r = [W]::Rect($h); $a = ($r.Rt - $r.L) * ($r.B - $r.T)
      if ($a -gt $area) { $best = $h; $area = $a }
    }
    $h = [W]::GetWindow($h, 2)
  }
  $best
}

L "sampler start game=$Game"
$last = ""; $lastCpu = @{}; $tick = 0
while ($true) {
  $tick++
  $gp = @(Get-Process -Name $Game -ErrorAction SilentlyContinue)
  $fg = [W]::GetForegroundWindow()
  $line = "fg=$(PName ([W]::Pid($fg)))/$([W]::Cls($fg)) $(RS ([W]::Rect($fg)))"
  if ($gp.Count) {
    $gh = GameWindow ($gp | ForEach-Object Id)
    if ($gh -ne [IntPtr]::Zero) {
      $st = [W]::GetWindowLong($gh, -16); $ex = [W]::GetWindowLong($gh, -20)
      $flags = @()
      if ($st -band 0x80000000) { $flags += "popup" }; if ($st -band 0x00C00000) { $flags += "caption" }
      if ($ex -band 0x8) { $flags += "TOPMOST" }; if ([W]::IsIconic($gh)) { $flags += "MINIMISED" }; if ([W]::IsZoomed($gh)) { $flags += "maximised" }
      $ck = [W]::Cloak($gh); if ($ck) { $flags += "CLOAKED=$ck" }
      if ($fg -eq $gh) { $flags += "foreground" }
      $gr = [W]::Rect($gh)
      $line += " | game $(RS $gr) $($flags -join ',')"
      # visible, uncloaked windows ABOVE the game that overlap it (these break independent flip)
      $above = @(); $h = [W]::GetTopWindow([IntPtr]::Zero)
      while ($h -ne [IntPtr]::Zero -and $h -ne $gh) {
        if ([W]::IsWindowVisible($h) -and -not [W]::Cloak($h)) {
          $r = [W]::Rect($h)
          if ($r.Rt -gt $gr.L -and $r.L -lt $gr.Rt -and $r.B -gt $gr.T -and $r.T -lt $gr.B -and ($r.Rt - $r.L) -gt 0 -and ($r.B - $r.T) -gt 0) {
            $tm = if ([W]::GetWindowLong($h, -20) -band 0x8) { "T" } else { "" }
            $above += "$(PName ([W]::Pid($h)))/$([W]::Cls($h))$tm$(RS $r)"
          }
        }
        $h = [W]::GetWindow($h, 2)
      }
      $line += " | above: " + ($(if ($above.Count) { $above -join "; " } else { "none" }))
    } else { $line += " | game process, no visible window" }
  } else { $line += " | game not running" }
  if ($line -ne $last) { L $line; $last = $line }

  if ($tick % 4 -eq 0) {
    $now = Get-Date; $parts = @()
    foreach ($p in Get-Process -Name $Game, glazewm, zebar, msedgewebview2, AutoHotkey64_UIA, dwm, PowerToys.FancyZones, WindowsTerminal -ErrorAction SilentlyContinue) {
      $k = $p.Id; $t = $p.TotalProcessorTime.TotalMilliseconds
      if ($lastCpu.ContainsKey($k)) {
        $pct = ($t - $lastCpu[$k][0]) / ($now - $lastCpu[$k][1]).TotalMilliseconds * 100 / [Environment]::ProcessorCount
        if ($pct -ge 0.5 -or $p.ProcessName -eq $Game) { $parts += "$($p.ProcessName)#$k=$([math]::Round($pct,1))%" }
      }
      $lastCpu[$k] = @($t, $now)
    }
    if ($parts.Count) { L ("cpu " + ($parts -join " ")) }
  }
  if ($tick % 12 -eq 0) {
    try {
      $s = (Get-Counter '\GPU Engine(*engtype_3D)\Utilization Percentage' -ErrorAction Stop).CounterSamples
      $byPid = $s | Group-Object { if ($_.InstanceName -match 'pid_(\d+)') { [int]$matches[1] } else { 0 } } |
        ForEach-Object { [pscustomobject]@{ Pid = $_.Name; U = ($_.Group | Measure-Object CookedValue -Sum).Sum } } |
        Where-Object U -ge 1 | Sort-Object U -Descending | Select-Object -First 6
      L ("gpu3d " + (($byPid | ForEach-Object { "$(PName ([int]$_.Pid))#$($_.Pid)=$([math]::Round($_.U,1))%" }) -join " "))
    } catch { L "gpu counter error: $_" }
  }
  Start-Sleep -Milliseconds 500
}
