Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Text;
public class Mon {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l,t,r,b; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONITORINFOEX {
    public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string szDevice; }
  public delegate bool Proc(IntPtr h, IntPtr dc, ref RECT r, IntPtr d);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr a, IntPtr b, Proc c, IntPtr d);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFOEX mi);
  [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr h, int t, out uint x, out uint y);
  public static string Dump() {
    var sb = new StringBuilder();
    EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr h, IntPtr dc, ref RECT r, IntPtr d) => {
      var mi = new MONITORINFOEX(); mi.cbSize = Marshal.SizeOf(mi); GetMonitorInfo(h, ref mi);
      uint dx, dy; GetDpiForMonitor(h, 0, out dx, out dy);
      sb.AppendLine(string.Format("{0} mon[{1},{2} {3}x{4}] work[{5},{6} {7}x{8}] dpi={9} primary={10}", mi.szDevice,
        mi.rcMonitor.l, mi.rcMonitor.t, mi.rcMonitor.r-mi.rcMonitor.l, mi.rcMonitor.b-mi.rcMonitor.t,
        mi.rcWork.l, mi.rcWork.t, mi.rcWork.r-mi.rcWork.l, mi.rcWork.b-mi.rcWork.t, dx, (mi.dwFlags & 1) != 0));
      return true; }, IntPtr.Zero);
    return sb.ToString(); }
}
"@
[Mon]::Dump()
