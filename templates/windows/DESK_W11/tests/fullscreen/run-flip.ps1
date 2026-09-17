param([string]$ArgsLine)
$p = Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList $ArgsLine -PassThru
$p.WaitForExit()
"exit $($p.ExitCode) pid $($p.Id)"
