#Requires -Version 7

$connections = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue

foreach ($conn in $connections) {
    $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Port = $conn.LocalPort
        State = $conn.State
        PID = $conn.OwningProcess
        ProcessName = if($proc){$proc.Name}else{'Unknown'}
        Path = if($proc){$proc.Path}else{'N/A'}
    }
}
