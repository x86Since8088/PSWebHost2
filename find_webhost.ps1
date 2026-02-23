#Requires -Version 7

$processes = Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" -ErrorAction SilentlyContinue

foreach ($proc in $processes) {
    if ($proc.CommandLine -like '*WebHost.ps1*') {
        [PSCustomObject]@{
            PID = $proc.ProcessId
            CommandLine = $proc.CommandLine
        }
    }
}
