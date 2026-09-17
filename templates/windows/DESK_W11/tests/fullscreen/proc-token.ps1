# Passive check (same access Task Manager uses): is <name> elevated / what integrity level?
param([string]$Name = "AION2")
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class Tok {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(uint a, bool i, int pid);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr p, uint a, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool GetTokenInformation(IntPtr t, int c, IntPtr b, int l, out int r);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  public static string Check(int pid) {
    IntPtr p = OpenProcess(0x1000, false, pid);
    if (p == IntPtr.Zero) return "OpenProcess(QUERY_LIMITED) failed err=" + Marshal.GetLastWin32Error();
    IntPtr t;
    if (!OpenProcessToken(p, 0x8, out t)) { int e = Marshal.GetLastWin32Error(); CloseHandle(p); return "OpenProcessToken failed err=" + e + (e == 5 ? " (access denied: higher integrity or protected)" : ""); }
    IntPtr b = Marshal.AllocHGlobal(64); int r; string s = "";
    if (GetTokenInformation(t, 20, b, 64, out r)) s += "elevated=" + (Marshal.ReadInt32(b) != 0);
    if (GetTokenInformation(t, 25, b, 64, out r)) { IntPtr sid = Marshal.ReadIntPtr(b); int n = Marshal.ReadByte(sid, 1); s += " integrityRID=0x" + Marshal.ReadInt32(sid, 8 + 4 * (n - 1)).ToString("x"); }
    Marshal.FreeHGlobal(b); CloseHandle(t); CloseHandle(p); return s;
  }
}
"@
$me = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
foreach ($p in Get-Process -Name $Name -EA SilentlyContinue) { "$($p.ProcessName)#$($p.Id) (checker elevated=$me): $([Tok]::Check($p.Id))" }
