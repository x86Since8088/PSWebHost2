# This script deeply inspects $Global:PSWebServer.Apps
$ProjectRoot = "C:\SC\PsWebHost"
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

Write-Host "`n=== Deep Inspection of `$Global:PSWebServer.Apps ===" -ForegroundColor Cyan

$apps = $Global:PSWebServer.Apps

Write-Host "`nTotal Apps: $($apps.Count)" -ForegroundColor Yellow
Write-Host "App Names: $($apps.Keys -join ', ')`n" -ForegroundColor Gray

foreach ($appName in ($apps.Keys | Sort-Object)) {
    $app = $apps[$appName]

    Write-Host "`n$appName" -ForegroundColor Yellow
    Write-Host "  Type: $($app.GetType().Name)" -ForegroundColor Gray

    if ($app -is [hashtable] -or $app -is [System.Collections.IDictionary]) {
        Write-Host "  Keys: $($app.Keys.Count)" -ForegroundColor Gray

        foreach ($key in ($app.Keys | Sort-Object)) {
            $value = $app[$key]
            $type = if ($value) { $value.GetType().Name } else { "null" }

            Write-Host "    $key [$type]" -NoNewline -ForegroundColor White

            # Try to measure this specific property
            try {
                if ($value -is [System.Collections.ICollection]) {
                    Write-Host " - Count: $($value.Count)" -NoNewline -ForegroundColor Gray
                }

                # Measure JSON size
                $jsonJob = Start-Job -ScriptBlock {
                    param($Value)
                    try {
                        ($Value | ConvertTo-Json -Depth 10 -Compress).Length
                    }
                    catch {
                        "Error: $($_.Exception.Message)"
                    }
                } -ArgumentList $value

                $completed = Wait-Job -Job $jsonJob -Timeout 3

                if ($completed) {
                    $jsonSize = Receive-Job -Job $jsonJob
                    if ($jsonSize -is [int]) {
                        if ($jsonSize -gt 10240) {
                            Write-Host " - $([math]::Round($jsonSize/1KB, 2)) KB" -ForegroundColor Red
                        }
                        elseif ($jsonSize -gt 1024) {
                            Write-Host " - $([math]::Round($jsonSize/1KB, 2)) KB" -ForegroundColor Yellow
                        }
                        else {
                            Write-Host " - $jsonSize bytes" -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Host " - $jsonSize" -ForegroundColor Red
                    }
                }
                else {
                    Stop-Job -Job $jsonJob
                    Write-Host " - TIMEOUT" -ForegroundColor Red
                }

                Remove-Job -Job $jsonJob -Force
            }
            catch {
                Write-Host " - ERROR: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
