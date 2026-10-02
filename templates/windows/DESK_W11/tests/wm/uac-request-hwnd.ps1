# Asks for elevation the way an installer working in the background does:
# ShellExecuteEx with hwnd = its own window, while that window is NOT the
# foreground one. Windows then parks the prompt as a minimised shield on the
# primary monitor's taskbar instead of switching to the secure desktop
# (measured 2026-10-02; with hwnd 0, as Start-Process -Verb RunAs does it, the
# prompt always comes to the front, so that never reproduced anything).
# The elevated command is `cmd /c exit`: answering Yes or No changes nothing.
param([int]$Delay = 2, [int]$Stay = 60)
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System; using System.IO; using System.Runtime.InteropServices; using System.Threading; using System.Windows.Forms;
public class QuietForm : Form { protected override bool ShowWithoutActivation { get { return true; } } }
public static class Asker {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct SEI { public int cbSize; public uint fMask; public IntPtr hwnd; public string lpVerb; public string lpFile; public string lpParameters; public string lpDirectory; public int nShow; public IntPtr hInstApp; public IntPtr lpIDList; public string lpClass; public IntPtr hkeyClass; public uint dwHotKey; public IntPtr hIcon; public IntPtr hProcess; }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool ShellExecuteExW(ref SEI i);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  public static void Ask(IntPtr hwnd, string asked, string result) {
    var t = new Thread(() => {
      File.WriteAllText(asked, "asking " + DateTime.Now.ToString("HH:mm:ss.fff") + " hwnd=0x" + hwnd.ToInt64().ToString("x") + " fg=0x" + GetForegroundWindow().ToInt64().ToString("x"));
      var i = new SEI(); i.cbSize = Marshal.SizeOf(typeof(SEI)); i.hwnd = hwnd; i.lpVerb = "runas"; i.lpFile = "cmd.exe"; i.lpParameters = "/c exit"; i.nShow = 0;
      bool ok = ShellExecuteExW(ref i); int e = Marshal.GetLastWin32Error();
      File.WriteAllText(result, (ok ? "accepted" : "declined or failed: win32 " + e) + " " + DateTime.Now.ToString("HH:mm:ss"));
    });
    t.SetApartmentState(ApartmentState.STA); t.IsBackground = true; t.Start();
  }
}
'@
$f = New-Object QuietForm
$f.Text = 'UAC probe (background app)'; $f.Width = 420; $f.Height = 180; $f.FormBorderStyle = "FixedDialog"; $f.MaximizeBox = $false; $f.StartPosition = "Manual"; $f.Left = 200; $f.Top = 200
$asked = "$env:TEMP\perf\uac-request.asked"; $result = "$env:TEMP\perf\uac-request.out"
$t1 = New-Object System.Windows.Forms.Timer; $t1.Interval = $Delay * 1000
$t1.Add_Tick({ $t1.Stop(); [Asker]::Ask($f.Handle, $asked, $result) })
$t2 = New-Object System.Windows.Forms.Timer; $t2.Interval = $Stay * 1000
$t2.Add_Tick({ $t2.Stop(); $f.Close() })
$f.Add_Shown({ $t1.Start(); $t2.Start() })
[System.Windows.Forms.Application]::Run($f)
