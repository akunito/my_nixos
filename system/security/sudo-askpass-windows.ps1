# sudo askpass for NixOS-WSL: a native Windows password box, started through
# interop, that writes the password to stdout.
#
# Why not zenity: WSLg on DESK_W11 has no usable vGPU and runs in copy mode
# (weston.log: rdp_allocate_shared_memory ... Input/output error at every
# boot), and in that state it paints the FIRST Linux window after a boot and
# no other -- right place, right size, empty surface, with AkuWM stopped too
# (measured 2026-10-02 15:40). A deploy waited on an invisible password box
# three times that day.
param(
    [string] $Prompt = 'sudo: authentication required',
    # Test hook: fill this in and press OK after 700 ms, to prove the pipe and
    # the encoding without a person.
    [string] $SelfTest = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(System.Drawing.Point p, uint f); [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr m, int t, out uint x, out uint y);' -Name N -Namespace AskPass -ReferencedAssemblies System.Drawing
# Per-monitor aware BEFORE any window exists: the box is centred on the screen
# under the pointer, and on this desk those have three different scales.
[AskPass.N]::SetProcessDpiAwarenessContext([IntPtr]-4) | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

$screen = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position)
# The scale of the monitor under the pointer (150 / 125 / 100 % on this desk);
# a guess from the pixel height made the box 753 px wide on the portrait one.
$dx = [uint32]96; $dy = [uint32]96
[AskPass.N]::GetDpiForMonitor([AskPass.N]::MonitorFromPoint([System.Windows.Forms.Cursor]::Position, 2), 0, [ref]$dx, [ref]$dy) | Out-Null
$scale = [Math]::Max(1.0, $dx / 96.0)
$form = New-Object System.Windows.Forms.Form
$form.Text = 'sudo'
$form.FormBorderStyle = 'FixedDialog'      # not resizable: AkuWM floats it instead of tiling it
$form.MaximizeBox = $false; $form.MinimizeBox = $false
$form.TopMost = $true; $form.ShowInTaskbar = $true
$form.StartPosition = 'Manual'
$form.Font = New-Object System.Drawing.Font('Segoe UI', [float](10 * $scale))
$form.ClientSize = New-Object System.Drawing.Size ([int](420 * $scale)), ([int](150 * $scale))
$form.Location = New-Object System.Drawing.Point `
    ([int]($screen.WorkingArea.X + ($screen.WorkingArea.Width - $form.Width) / 2)), `
    ([int]($screen.WorkingArea.Y + ($screen.WorkingArea.Height - $form.Height) / 2))

$label = New-Object System.Windows.Forms.Label
$label.Text = $Prompt; $label.AutoSize = $false
$label.SetBounds([int](16 * $scale), [int](14 * $scale), [int](388 * $scale), [int](40 * $scale))
$box = New-Object System.Windows.Forms.TextBox
$box.UseSystemPasswordChar = $true
$box.SetBounds([int](16 * $scale), [int](58 * $scale), [int](388 * $scale), [int](28 * $scale))
$ok = New-Object System.Windows.Forms.Button
$ok.Text = 'OK'; $ok.DialogResult = 'OK'
$ok.SetBounds([int](212 * $scale), [int](102 * $scale), [int](92 * $scale), [int](32 * $scale))
$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'; $cancel.DialogResult = 'Cancel'
$cancel.SetBounds([int](312 * $scale), [int](102 * $scale), [int](92 * $scale), [int](32 * $scale))
$form.Controls.AddRange(@($label, $box, $ok, $cancel))
$form.AcceptButton = $ok; $form.CancelButton = $cancel
$form.Add_Shown({
    # Started from a background process, the box is not the foreground window
    # by right; ask for it, and put the caret in the field either way.
    [AskPass.N]::SetForegroundWindow($form.Handle) | Out-Null
    $form.Activate(); $box.Focus() | Out-Null
})
if ($SelfTest) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 700
    $timer.Add_Tick({ $timer.Stop(); $box.Text = $SelfTest; $ok.PerformClick() })
    $timer.Start()
}

$result = $form.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }
# UTF-8 without a BOM and a bare LF: sudo reads one line from the pipe, and the
# console's OEM code page would turn every non-ASCII character into another.
$out = [Console]::OpenStandardOutput()
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($box.Text + "`n")
$out.Write($bytes, 0, $bytes.Length); $out.Flush()
exit 0
