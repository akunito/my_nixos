Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class W {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
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

# Focus follows the mouse on this desktop, so every test has to say where the
# pointer is: a pointer resting over another monitor takes the focus away from
# the window under test and Windows then composes it. GlazeWM only reacts to
# real movement, so the pointer is walked with injected relative moves instead
# of being teleported with SetCursorPos.
[void][W]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Drawing;
public static class Mouse {
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
}
"@ -ReferencedAssemblies System.Drawing
function WalkCursorTo($x, $y) {
  for ($i = 0; $i -lt 80; $i++) {
    $c = New-Object System.Drawing.Point
    [void][Mouse]::GetCursorPos([ref]$c)
    $dx = [math]::Sign($x - $c.X) * [math]::Min(80, [math]::Abs($x - $c.X))
    $dy = [math]::Sign($y - $c.Y) * [math]::Min(80, [math]::Abs($y - $c.Y))
    if ($dx -eq 0 -and $dy -eq 0) { break }
    [Mouse]::mouse_event(0x0001, $dx, $dy, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 25
  }
  # Injected relative moves go through the pointer acceleration, so they land
  # near the target, not on it: finish with an exact placement.
  [void][W]::SetCursorPos($x, $y)
  Start-Sleep -Milliseconds 400
}
function ParkCursorOn($rect) { WalkCursorTo ([int]($rect.L + ($rect.Rt - $rect.L) / 2)) ([int]($rect.T + ($rect.B - $rect.T) / 2)) }
function ParkCursorOnPrimary {
  $b = ([System.Windows.Forms.Screen]::AllScreens | ? Primary).Bounds
  WalkCursorTo ([int]($b.Left + $b.Width / 2)) ([int]($b.Top + $b.Height / 2))
}
function ParkCursorOnSecondary {
  $b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary } | Select-Object -First 1).Bounds
  if ($b) { WalkCursorTo ([int]($b.Left + $b.Width / 2)) ([int]($b.Top + $b.Height / 2)) }
}

# Hovering focuses after a moment, and GlazeWM re-syncs focus of its own: poll
# instead of sampling once, so the test measures the settled state.
function WaitForFocus($hwnd, $timeoutMs = 3000) {
  $deadline = (Get-Date).AddMilliseconds($timeoutMs)
  while ((Get-Date) -lt $deadline) {
    if ([W]::GetForegroundWindow() -eq $hwnd) { return $true }
    Start-Sleep -Milliseconds 200
  }
  $false
}
