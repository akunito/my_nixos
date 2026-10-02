# A native Windows password / confirmation box for NixOS-WSL, started through
# interop. Two callers: the sudo askpass (sudo.nix) and the gpg pinentry
# (pinentry-windows.sh). The password goes to stdout.
#
# Why not a Linux dialog: WSLg on DESK_W11 has no usable vGPU and runs in copy
# mode (weston.log: rdp_allocate_shared_memory ... Input/output error at every
# boot), and in that state it paints the FIRST Linux window after a boot and
# no other -- right place, right size, empty surface, with AkuWM stopped too
# (measured 2026-10-02 15:40). A deploy waited on an invisible password box
# three times that day.
#
# Exit codes: 0 = OK (password on stdout unless -Confirm), 1 = cancelled.
param(
    [string] $Prompt = 'sudo: authentication required',
    # Everything else arrives in a JSON file (UTF-8): title, description, error,
    # prompt, ok, cancel, confirm, repeat. Strings from gpg carry quotes and
    # newlines that would not survive a command line through interop.
    [string] $ParamFile = '',
    # Test hook: fill the field(s) with this and press OK after 700 ms, to
    # prove the pipe and the encoding without a person.
    [string] $SelfTest = ''
)
$ErrorActionPreference = 'Stop'
$p = @{ title = 'sudo'; description = ''; error = ''; prompt = $Prompt; ok = 'OK'; cancel = 'Cancel'; confirm = $false; repeat = $false }
if ($ParamFile) {
    $json = [System.IO.File]::ReadAllText($ParamFile, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    foreach ($k in @($p.Keys)) { if ($null -ne $json.$k -and "$($json.$k)" -ne '') { $p[$k] = $json.$k } }
}
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
function S([double] $v) { [int]($v * $scale) }

$form = New-Object System.Windows.Forms.Form
$form.Text = [string]$p.title
$form.FormBorderStyle = 'FixedDialog'      # not resizable: AkuWM floats it instead of tiling it
$form.MaximizeBox = $false; $form.MinimizeBox = $false
$form.TopMost = $true; $form.ShowInTaskbar = $true
$form.StartPosition = 'Manual'
$form.Font = New-Object System.Drawing.Font('Segoe UI', [float](10 * $scale))

$width = 460; $y = 14
$controls = New-Object System.Collections.ArrayList
function AddLabel([string] $text, [System.Drawing.Color] $colour) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.ForeColor = $colour; $l.AutoSize = $false
    $l.MaximumSize = New-Object System.Drawing.Size (S ($width - 32)), 0
    $size = $l.GetPreferredSize((New-Object System.Drawing.Size (S ($width - 32)), 0))
    $h = [Math]::Max((S 22), $size.Height)
    $l.SetBounds((S 16), (S $script:y), (S ($width - 32)), $h)
    $script:y += [int]($h / $scale) + 8
    [void]$controls.Add($l)
}
if ($p.error)       { AddLabel ([string]$p.error) ([System.Drawing.Color]::Firebrick) }
if ($p.description) { AddLabel ([string]$p.description) ([System.Drawing.SystemColors]::ControlText) }
$box = $null; $box2 = $null
if (-not $p.confirm) {
    AddLabel ([string]$p.prompt) ([System.Drawing.SystemColors]::ControlText)
    $box = New-Object System.Windows.Forms.TextBox
    $box.UseSystemPasswordChar = $true
    $box.SetBounds((S 16), (S $y), (S ($width - 32)), (S 28)); $y += 38
    [void]$controls.Add($box)
    if ($p.repeat) {
        AddLabel 'Repeat:' ([System.Drawing.SystemColors]::ControlText)
        $box2 = New-Object System.Windows.Forms.TextBox
        $box2.UseSystemPasswordChar = $true
        $box2.SetBounds((S 16), (S $y), (S ($width - 32)), (S 28)); $y += 38
        [void]$controls.Add($box2)
    }
}
$y += 6
$ok = New-Object System.Windows.Forms.Button
$ok.Text = [string]$p.ok
$ok.SetBounds((S ($width - 216)), (S $y), (S 96), (S 32))
$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = [string]$p.cancel; $cancel.DialogResult = 'Cancel'
$cancel.SetBounds((S ($width - 112)), (S $y), (S 96), (S 32))
[void]$controls.Add($ok); [void]$controls.Add($cancel)
$form.ClientSize = New-Object System.Drawing.Size (S $width), (S ($y + 46))
$form.Controls.AddRange($controls.ToArray())
$form.AcceptButton = $ok; $form.CancelButton = $cancel
$form.Location = New-Object System.Drawing.Point `
    ([int]($screen.WorkingArea.X + ($screen.WorkingArea.Width - $form.Width) / 2)), `
    ([int]($screen.WorkingArea.Y + ($screen.WorkingArea.Height - $form.Height) / 2))
$ok.Add_Click({
    # A new passphrase typed twice must match before the box lets go.
    if ($box2 -and $box.Text -cne $box2.Text) {
        $box2.Text = ''; $form.Text = "$($p.title) - the two do not match"; $box2.Focus() | Out-Null
        return
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
})
$form.Add_Shown({
    # Started from a background process, the box is not the foreground window
    # by right; ask for it, and put the caret in the field either way.
    [AskPass.N]::SetForegroundWindow($form.Handle) | Out-Null
    $form.Activate()
    if ($box) { $box.Focus() | Out-Null } else { $ok.Focus() | Out-Null }
})
if ($SelfTest) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 700
    $timer.Add_Tick({ $timer.Stop(); if ($box) { $box.Text = $SelfTest }; if ($box2) { $box2.Text = $SelfTest }; $ok.PerformClick() })
    $timer.Start()
}

$result = $form.ShowDialog()
if ($result -ne [System.Windows.Forms.DialogResult]::OK) { exit 1 }
if ($box) {
    # UTF-8 without a BOM and a bare LF: the caller reads one line from the
    # pipe, and the console's OEM code page would turn every non-ASCII
    # character into another.
    $out = [Console]::OpenStandardOutput()
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($box.Text + "`n")
    $out.Write($bytes, 0, $bytes.Length); $out.Flush()
}
exit 0
