$p = Start-Process "$env:TEMP\perf\fliptest.exe" -ArgumentList "25 0" -PassThru
"started pid $($p.Id)"; $p.WaitForExit(); "exited"
