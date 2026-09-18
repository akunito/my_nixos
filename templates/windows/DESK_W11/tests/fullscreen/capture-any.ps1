# Elevated: capture every process' frames for N seconds (for games whose exe we
# don't know yet). Usage through the daemon: echo "capture-any.ps1 40" > x.elev
param([int]$Seconds = 40)
& "$env:TEMP\perf\PresentMon.exe" --output_file "$env:TEMP\perf\any.csv" --v2_metrics --date_time --timed $Seconds --terminate_after_timed --stop_existing_session --session_name AkuAny --no_console_stats *> $null
"captured $Seconds s"
