# The system credential prompt is left alone by the window manager: it stays
# where Windows put it, at the size Windows gave it, and is not a window of
# any workspace (rule r-credential-ui, 2026-10-02 -- managed, it was dragged to
# the monitor under the pointer and fought over its size for as long as it lived).
Add-Type -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
public struct POINT { public int X, Y; }
public struct RECT { public int L, T, R, B; }
'@ -Name C -Namespace W
[W.C]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null
$perf = "$env:TEMP\perf"
function RectOf($h) { $r = New-Object W.C+RECT; [W.C]::GetWindowRect($h, [ref]$r) | Out-Null; "{0},{1} {2}x{3}" -f $r.L, $r.T, ($r.R - $r.L), ($r.B - $r.T) }
Get-Process CredentialUIBroker -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
# The pointer on the OTHER monitor: the prompt is born on the primary one, and
# a managed window is taken to the monitor under the pointer -- that trip, to
# a screen with another scale, is where the fight over the size was.
Add-Type -AssemblyName System.Windows.Forms
$was = New-Object W.C+POINT; [W.C]::GetCursorPos([ref]$was) | Out-Null
$other = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
if ($other) { [W.C]::SetCursorPos($other.Bounds.X + [int]($other.Bounds.Width / 2), $other.Bounds.Y + [int]($other.Bounds.Height / 2)) | Out-Null; Start-Sleep -Milliseconds 300 }
$asker = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $perf\credui-ask.ps1"
$h = [IntPtr]::Zero
foreach ($i in 1..60) {
  Start-Sleep -Milliseconds 100
  $b = Get-Process CredentialUIBroker -EA SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($b) { $h = $b.MainWindowHandle; break }
}
if ($h -eq [IntPtr]::Zero) { "FAIL the credential prompt never appeared"; Stop-Process -Id $asker.Id -Force -EA SilentlyContinue; exit 1 }
"PASS the credential prompt appeared"
# It is born cloaked over the whole work area (0,42 3840x2118 here) and takes
# its real rectangle as it uncloaks: sampling starts after that.
foreach ($i in 1..30) { $cl = 1; [W.C]::DwmGetWindowAttribute($h, 14, [ref]$cl, 4) | Out-Null; if ($cl -eq 0 -and [W.C]::IsWindowVisible($h)) { break }; Start-Sleep -Milliseconds 100 }
Start-Sleep -Milliseconds 400
# Sampled for three seconds: one rectangle, the one Windows gave it.
$seen = New-Object System.Collections.Generic.List[string]
foreach ($i in 1..30) { $r = RectOf $h; if (-not $seen.Contains($r)) { $seen.Add($r) }; Start-Sleep -Milliseconds 100 }
$primary = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$r0 = New-Object W.C+RECT; [W.C]::GetWindowRect($h, [ref]$r0) | Out-Null
$onPrimary = $r0.L -ge $primary.X -and $r0.R -le $primary.Right -and $r0.T -ge $primary.Y -and $r0.B -le $primary.Bottom
if ($seen.Count -eq 1 -and $onPrimary) { "PASS it stayed where Windows put it ($($seen[0]), on the primary monitor, the pointer on the other)" }
elseif ($seen.Count -eq 1) { "FAIL it is not on the primary monitor where Windows shows it: $($seen[0])" }
else { "FAIL it was moved or resized: $($seen -join ' -> ')" }
$cli = "C:\Program Files\AkuWM\akuwm-cli.exe"
$layout = & $cli debug layout | Out-String
if ($layout -match '"process":\s*"CredentialUIBroker"') { "FAIL the window manager holds it as a window of a workspace" } else { "PASS it is not a window of any workspace" }
$cl = 0; [W.C]::DwmGetWindowAttribute($h, 14, [ref]$cl, 4) | Out-Null
if ([W.C]::IsWindowVisible($h) -and $cl -eq 0) { "PASS it is visible and not cloaked" } else { "FAIL it is hidden (visible=$([W.C]::IsWindowVisible($h)) cloak=$cl)" }
Get-Process CredentialUIBroker -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Milliseconds 500
[W.C]::SetCursorPos($was.X, $was.Y) | Out-Null
Stop-Process -Id $asker.Id -Force -EA SilentlyContinue
