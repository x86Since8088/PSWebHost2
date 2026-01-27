# This script loads the WebHost environment and measures variable sizes
$ProjectRoot = "C:\SC\PsWebHost"
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

Write-Host "`n=== Measuring Global Variable Sizes ===" -ForegroundColor Cyan

$variables = @{
    'PSWebSessions' = '$Global:PSWebSessions'
    'PSWebServer' = '$Global:PSWebServer'
    'LogHistory' = '$Global:LogHistory'
    'PSDefaultParameterValues' = '$Global:PSDefaultParameterValues'
    'Error' = '$Global:Error'
    'PSVersionTable' = '$Global:PSVersionTable'
}

foreach ($name in $variables.Keys | Sort-Object) {
    $varExpr = $variables[$name]
    try {
        Write-Host "`n$name ($varExpr):" -ForegroundColor Yellow

        # Get count if it's a collection
        $countResult = Invoke-Expression "if ($varExpr -is [System.Collections.ICollection]) { $varExpr.Count } else { 'N/A' }"
        Write-Host "  Count: $countResult" -ForegroundColor Gray

        # Try to get JSON size with timeout
        $jsonJob = Start-Job -ScriptBlock {
            param($VarExpr)
            try {
                $var = Invoke-Expression $VarExpr
                ($var | ConvertTo-Json -Depth 15 -Compress).Length
            }
            catch {
                "Error: $($_.Exception.Message)"
            }
        } -ArgumentList $varExpr

        $completed = Wait-Job -Job $jsonJob -Timeout 10

        if ($completed) {
            $jsonSize = Receive-Job -Job $jsonJob
            Write-Host "  JSON Size (depth 15): $jsonSize bytes" -ForegroundColor Green
        }
        else {
            Stop-Job -Job $jsonJob
            Write-Host "  JSON Size: TIMEOUT (>10s to serialize)" -ForegroundColor Red
        }

        Remove-Job -Job $jsonJob -Force

        # Try to get memory size estimate
        $sizeJob = Start-Job -ScriptBlock {
            param($VarExpr)
            try {
                $var = Invoke-Expression $VarExpr
                $ms = [System.IO.MemoryStream]::new()
                $bf = [System.Runtime.Serialization.Formatters.Binary.BinaryFormatter]::new()
                $bf.Serialize($ms, $var)
                $ms.Length
            }
            catch {
                "Error: $($_.Exception.Message)"
            }
        } -ArgumentList $varExpr

        $completed = Wait-Job -Job $sizeJob -Timeout 5

        if ($completed) {
            $memSize = Receive-Job -Job $sizeJob
            Write-Host "  Binary Size (approx): $memSize bytes" -ForegroundColor Cyan
        }
        else {
            Stop-Job -Job $sizeJob
            Write-Host "  Binary Size: TIMEOUT" -ForegroundColor Red
        }

        Remove-Job -Job $sizeJob -Force
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
