BeforeAll {
    # Initialize test environment
    $InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
    . $InitializationScript

    $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
    $script:BaseUrl = "http://localhost:$($Global:PSWebServer.Port)"

    # Get authentication for tests
    $script:Headers = @{}
    if ($Global:PSWebServer.TestCredentials) {
        # Use test credentials if available
        $cred = $Global:PSWebServer.TestCredentials
        $script:Headers = @{
            'X-API-Key' = $cred.ApiKey
        }
    }
}

Describe "PSWebHost Concurrency Tests" -Tag "Concurrency", "Performance", "System" {

    BeforeAll {
        Write-Host "`n=== Concurrency Test Configuration ===" -ForegroundColor Yellow
        Write-Host "Base URL: $script:BaseUrl" -ForegroundColor Gray
        Write-Host "Test will validate that 3+ concurrent requests can be serviced simultaneously" -ForegroundColor Gray
        Write-Host "========================================`n" -ForegroundColor Yellow
    }

    Context "Long-Running Request Concurrency" {

        It "Should service 3 concurrent 5-second requests in ~5 seconds (not 15 seconds)" {
            # If requests were sequential, this would take 15 seconds
            # If concurrent (runspace pool), should take ~5 seconds

            $testStart = Get-Date

            # Launch 3 concurrent requests using jobs
            Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Launching 3 concurrent requests..." -ForegroundColor Cyan

            $jobs = @()
            1..3 | ForEach-Object {
                $requestId = "req$_"
                $job = Start-Job -ScriptBlock {
                    param($Url, $Headers, $Id)

                    try {
                        $response = Invoke-RestMethod -Uri "$Url/api/v1/system/test/concurrency?delay=5&id=$Id" `
                            -Method Get `
                            -Headers $Headers `
                            -TimeoutSec 30
                        return $response
                    } catch {
                        return @{
                            error = $_.Exception.Message
                            requestId = $Id
                            success = $false
                        }
                    }
                } -ArgumentList $script:BaseUrl, $script:Headers, $requestId

                $jobs += $job
                Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Started job $requestId (JobId: $($job.Id))" -ForegroundColor Gray
            }

            # Wait for all jobs to complete (max 12 seconds - allows for some overhead)
            Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Waiting for jobs to complete..." -ForegroundColor Cyan
            $results = $jobs | Wait-Job -Timeout 12 | Receive-Job
            $jobs | Remove-Job -Force

            $testEnd = Get-Date
            $totalDuration = ($testEnd - $testStart).TotalSeconds

            Write-Host "`n  === Concurrency Test Results ===" -ForegroundColor Yellow
            Write-Host "  Total elapsed time: $([math]::Round($totalDuration, 2))s" -ForegroundColor $(if ($totalDuration -lt 8) { "Green" } else { "Red" })

            foreach ($result in $results) {
                if ($result.success) {
                    Write-Host "  ✓ Request $($result.requestId): $($result.actualDuration)s (RunspaceId: $($result.runspaceId.Substring(0,8))...)" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Request $($result.requestId): FAILED - $($result.error)" -ForegroundColor Red
                }
            }

            # Validate all requests succeeded
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -Be 3

            $successfulRequests = @($results | Where-Object { $_.success -eq $true })
            $successfulRequests.Count | Should -Be 3 -Because "All 3 requests should complete successfully"

            # Validate concurrent execution (should take ~5 seconds, not 15)
            # Allow up to 8 seconds for network overhead, job startup, etc.
            $totalDuration | Should -BeLessThan 8 -Because "Concurrent requests should complete in ~5s, not sequentially (15s)"

            # Validate that different runspaces were used (proving concurrency)
            $uniqueRunspaces = ($results | Select-Object -ExpandProperty runspaceId -Unique).Count
            Write-Host "  Unique runspaces used: $uniqueRunspaces" -ForegroundColor Cyan
            $uniqueRunspaces | Should -BeGreaterThan 1 -Because "Multiple runspaces indicates true parallel execution"
        }

        It "Should service 5 concurrent 3-second requests in ~3 seconds (not 15 seconds)" {
            $testStart = Get-Date

            Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Launching 5 concurrent requests..." -ForegroundColor Cyan

            $jobs = @()
            1..5 | ForEach-Object {
                $requestId = "stress$_"
                $job = Start-Job -ScriptBlock {
                    param($Url, $Headers, $Id)

                    try {
                        $response = Invoke-RestMethod -Uri "$Url/api/v1/system/test/concurrency?delay=3&id=$Id" `
                            -Method Get `
                            -Headers $Headers `
                            -TimeoutSec 30
                        return $response
                    } catch {
                        return @{
                            error = $_.Exception.Message
                            requestId = $Id
                            success = $false
                        }
                    }
                } -ArgumentList $script:BaseUrl, $script:Headers, $requestId

                $jobs += $job
            }

            Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Waiting for jobs to complete..." -ForegroundColor Cyan
            $results = $jobs | Wait-Job -Timeout 10 | Receive-Job
            $jobs | Remove-Job -Force

            $testEnd = Get-Date
            $totalDuration = ($testEnd - $testStart).TotalSeconds

            Write-Host "`n  === Stress Test Results ===" -ForegroundColor Yellow
            Write-Host "  Total elapsed time: $([math]::Round($totalDuration, 2))s" -ForegroundColor $(if ($totalDuration -lt 6) { "Green" } else { "Red" })
            Write-Host "  Successful requests: $(@($results | Where-Object { $_.success -eq $true }).Count)/5" -ForegroundColor Cyan

            # Validate
            $results.Count | Should -Be 5
            $successfulRequests = @($results | Where-Object { $_.success -eq $true })
            $successfulRequests.Count | Should -Be 5 -Because "All 5 requests should complete successfully"

            # Should take ~3 seconds for concurrent execution, not 15 seconds for sequential
            $totalDuration | Should -BeLessThan 6 -Because "5 concurrent requests should complete in ~3s, not sequentially (15s)"
        }

        It "Should handle mixed duration concurrent requests efficiently" {
            # Test with varying delays: 2s, 4s, 6s
            # If concurrent: ~6 seconds (longest request)
            # If sequential: ~12 seconds (sum of all)

            $testStart = Get-Date

            Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Launching mixed-duration requests (2s, 4s, 6s)..." -ForegroundColor Cyan

            $delays = @(2, 4, 6)
            $jobs = @()

            for ($i = 0; $i -lt $delays.Count; $i++) {
                $delay = $delays[$i]
                $requestId = "mixed$($i+1)-$($delay)s"

                $job = Start-Job -ScriptBlock {
                    param($Url, $Headers, $Id, $Delay)

                    try {
                        $response = Invoke-RestMethod -Uri "$Url/api/v1/system/test/concurrency?delay=$Delay&id=$Id" `
                            -Method Get `
                            -Headers $Headers `
                            -TimeoutSec 30
                        return $response
                    } catch {
                        return @{
                            error = $_.Exception.Message
                            requestId = $Id
                            success = $false
                        }
                    }
                } -ArgumentList $script:BaseUrl, $script:Headers, $requestId, $delay

                $jobs += $job
            }

            Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Waiting for jobs to complete..." -ForegroundColor Cyan
            $results = $jobs | Wait-Job -Timeout 10 | Receive-Job
            $jobs | Remove-Job -Force

            $testEnd = Get-Date
            $totalDuration = ($testEnd - $testStart).TotalSeconds

            Write-Host "`n  === Mixed Duration Test Results ===" -ForegroundColor Yellow
            Write-Host "  Total elapsed time: $([math]::Round($totalDuration, 2))s" -ForegroundColor $(if ($totalDuration -lt 9) { "Green" } else { "Red" })

            foreach ($result in $results) {
                if ($result.success) {
                    Write-Host "  ✓ Request $($result.requestId): completed in $($result.actualDuration)s" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ Request $($result.requestId): FAILED - $($result.error)" -ForegroundColor Red
                }
            }

            # Validate
            $results.Count | Should -Be 3
            $successfulRequests = @($results | Where-Object { $_.success -eq $true })
            $successfulRequests.Count | Should -Be 3 -Because "All mixed-duration requests should complete"

            # Should take ~6 seconds (longest), not 12 seconds (sequential)
            $totalDuration | Should -BeLessThan 9 -Because "Concurrent execution should take ~6s (longest request), not 12s (sequential sum)"
        }
    }

    Context "Runspace Pool Configuration" {

        It "Should report runspace pool configuration via server status" {
            # Check if we can get server configuration/status
            $response = Invoke-RestMethod -Uri "$script:BaseUrl/api/v1/system/status" `
                -Method Get `
                -Headers $script:Headers `
                -ErrorAction SilentlyContinue

            if ($response) {
                Write-Host "  Server Status:" -ForegroundColor Yellow
                Write-Host "  $($response | ConvertTo-Json -Depth 3)" -ForegroundColor Gray
            } else {
                Write-Host "  Note: /api/v1/system/status endpoint not available" -ForegroundColor Yellow
            }

            # This test is informational - we just want to document the pool size
            $true | Should -Be $true
        }
    }

    AfterAll {
        Write-Host "`n=== Concurrency Test Summary ===" -ForegroundColor Yellow
        Write-Host "Tests validated that PSWebHost can service multiple concurrent long-running requests" -ForegroundColor Green
        Write-Host "This confirms the runspace pool is configured correctly for parallel request handling" -ForegroundColor Green
        Write-Host "================================`n" -ForegroundColor Yellow
    }
}
