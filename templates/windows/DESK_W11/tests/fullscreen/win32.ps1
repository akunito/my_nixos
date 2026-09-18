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
# the window under test and Windows then composes it.
[void][W]::SetProcessDpiAwarenessContext([IntPtr](-4))
Add-Type -AssemblyName System.Windows.Forms
function ParkCursorOn($rect) { [void][W]::SetCursorPos([int]($rect.L + ($rect.Rt - $rect.L) / 2), [int]($rect.T + ($rect.B - $rect.T) / 2)) }
function ParkCursorOnPrimary {
  $b = ([System.Windows.Forms.Screen]::AllScreens | ? Primary).Bounds
  [void][W]::SetCursorPos([int]($b.Left + $b.Width / 2), [int]($b.Top + $b.Height / 2))
}
function ParkCursorOnSecondary {
  $b = ([System.Windows.Forms.Screen]::AllScreens | ? { -not $_.Primary } | Select-Object -First 1).Bounds
  if ($b) { [void][W]::SetCursorPos([int]($b.Left + $b.Width / 2), [int]($b.Top + $b.Height / 2)) }
}
