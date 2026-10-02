# Shows the system credential prompt ("Windows Security", CredentialUIBroker.exe)
# the way an application asking for credentials or Windows Hello does. Nothing
# is typed into it: the case kills the broker.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Cred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct INFO { public int cbSize; public IntPtr hwndParent; public string pszMessageText; public string pszCaptionText; public IntPtr hbmBanner; }
  [DllImport("credui.dll", CharSet = CharSet.Unicode)]
  public static extern int CredUIPromptForWindowsCredentialsW(ref INFO info, int err, ref uint pkg, IntPtr inBuf, uint inSize, out IntPtr outBuf, out uint outSize, ref bool save, int flags);
  public static int Ask() { var i = new INFO(); i.cbSize = Marshal.SizeOf(typeof(INFO)); i.pszMessageText = "AkuWM probe: press Cancel"; i.pszCaptionText = "AkuWM credential probe"; uint pkg = 0; IntPtr o; uint n; bool save = false; return CredUIPromptForWindowsCredentialsW(ref i, 0, ref pkg, IntPtr.Zero, 0, out o, out n, ref save, 1); }
}
'@
"result $([Cred]::Ask())" | Set-Content "$env:TEMP\perf\credui-ask.out"
