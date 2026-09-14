# ShareX "after capture" action: put the screenshot's path on the clipboard in
# WSL form (/mnt/c/Users/...), so it can be pasted straight into Claude Code
# running inside NixOS-WSL. ShareX calls it with the saved file as %input.
param([Parameter(Mandatory = $true)][string]$Path)
$drive = $Path.Substring(0, 1).ToLower()
$rest  = $Path.Substring(2).Replace('\', '/')
Set-Clipboard -Value "/mnt/$drive$rest"
