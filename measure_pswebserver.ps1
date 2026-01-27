# This script loads the WebHost environment and deeply inspects $Global:PSWebServer
$ProjectRoot = "C:\SC\PsWebHost"
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

Write-Host "`n=== Deep Inspection of `$Global:PSWebServer ===" -ForegroundColor Cyan

Write-Host "`nKeys in `$Global:PSWebServer:" -ForegroundColor Yellow
$Global:PSWebServer.Keys | Sort-Object | ForEach-Object {
    $key = $_
    $value = $Global:PSWebServer[$key]
    $type = $value.GetType().Name

    Write-Host "  $key [$type]" -NoNewline -ForegroundColor White

    # Try to measure each key
    try {
        if ($value -is [System.Collections.ICollection]) {
            Write-Host " - Count: $($value.Count)" -NoNewline -ForegroundColor Gray
        }

        # Measure JSON size for this key
        $jsonJob = Start-Job -ScriptBlock {
            param($Value)
            try {
                ($Value | ConvertTo-Json -Depth 15 -Compress).Length
            }
            catch {
                "Error: $($_.Exception.Message)"
            }
        } -ArgumentList $value

        $completed = Wait-Job -Job $jsonJob -Timeout 5

        if ($completed) {
            $jsonSize = Receive-Job -Job $jsonJob
            if ($jsonSize -is [int]) {
                if ($jsonSize -gt 10240) {
                    Write-Host " - JSON: $([math]::Round($jsonSize/1KB, 2)) KB" -ForegroundColor Red
                }
                elseif ($jsonSize -gt 1024) {
                    Write-Host " - JSON: $([math]::Round($jsonSize/1KB, 2)) KB" -ForegroundColor Yellow
                }
                else {
                    Write-Host " - JSON: $jsonSize bytes" -ForegroundColor Green
                }
            }
            else {
                Write-Host " - JSON: $jsonSize" -ForegroundColor Red
            }
        }
        else {
            Stop-Job -Job $jsonJob
            Write-Host " - JSON: TIMEOUT (>5s)" -ForegroundColor Red
        }

        Remove-Job -Job $jsonJob -Force
    }
    catch {
        Write-Host " - ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
