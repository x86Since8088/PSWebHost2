# Test Card Endpoints After Migration

Write-Host "`n===== Testing Card Endpoints After Migration =====" -ForegroundColor Cyan

$baseUrl = "http://localhost:8080"
$endpoints = @(
    "/cards/main-menu"
    "/cards/system-log"
    "/cards/memory-explorer"
    "/apps/dockermanager/cards/docker-manager"
    "/apps/WebhostFileExplorer/cards/file-explorer"
    "/apps/WebHostMetrics/cards/server-heatmap"
)

$results = @()

foreach ($endpoint in $endpoints) {
    $url = "$baseUrl$endpoint"
    Write-Host "`nTesting: $endpoint" -ForegroundColor Yellow

    try {
        # First request to get session cookie
        $response1 = Invoke-WebRequest -Uri $url -SessionVariable session -UseBasicParsing -ErrorAction Stop

        # Second request with session
        $response2 = Invoke-WebRequest -Uri $url -WebSession $session -UseBasicParsing -ErrorAction Stop

        $status = $response2.StatusCode
        $contentLength = $response2.Content.Length

        if ($status -eq 200 -and $contentLength -gt 0) {
            Write-Host "  ✓ SUCCESS - Status: $status, Content Length: $contentLength bytes" -ForegroundColor Green

            # Try to parse as JSON
            try {
                $json = $response2.Content | ConvertFrom-Json
                Write-Host "  ✓ Valid JSON response" -ForegroundColor Green
                $results += [PSCustomObject]@{
                    Endpoint = $endpoint
                    Status = "PASS"
                    StatusCode = $status
                    ContentLength = $contentLength
                }
            } catch {
                Write-Host "  ⚠ Not JSON (might be HTML)" -ForegroundColor Yellow
                $results += [PSCustomObject]@{
                    Endpoint = $endpoint
                    Status = "WARN"
                    StatusCode = $status
                    ContentLength = $contentLength
                }
            }
        } else {
            Write-Host "  × FAIL - Status: $status" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Endpoint = $endpoint
                Status = "FAIL"
                StatusCode = $status
                ContentLength = $contentLength
            }
        }
    } catch {
        Write-Host "  × ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Endpoint = $endpoint
            Status = "ERROR"
            StatusCode = "N/A"
            ContentLength = 0
        }
    }
}

Write-Host "`n===== Test Summary =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$totalCount = $results.Count

Write-Host "`nPassed: $passCount / $totalCount" -ForegroundColor $(if ($passCount -eq $totalCount) { "Green" } else { "Yellow" })
