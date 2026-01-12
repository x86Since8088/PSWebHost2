<#
.SYNOPSIS
    Manual concurrency test for PSWebHost

.DESCRIPTION
    This script validates that PSWebHost can handle multiple concurrent long-running requests.

    Prerequisites:
    1. PSWebHost server must be running
    2. You must have credentials with the 'debug' role
    3. Configure connection details below

.EXAMPLE
    .\manual-concurrency-test.ps1 -Port 8080 -ApiKey "your-api-key-here"
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Port = 8080,

    [Parameter(Mandatory=$false)]
    [string]$ApiKey = "",

    [Parameter(Mandatory=$false)]
    [string]$SessionId = ""
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Concurrency Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$BaseUrl = "http://localhost:$Port"

# Build headers
$Headers = @{}
if ($ApiKey) {
    $Headers['X-API-Key'] = $ApiKey
    Write-Host "Using API Key authentication" -ForegroundColor Green
} elseif ($SessionId) {
    $Headers['Cookie'] = "sessionid=$SessionId"
    Write-Host "Using Session ID authentication" -ForegroundColor Green
} else {
    Write-Host "WARNING: No authentication provided. Test may fail if endpoint requires auth." -ForegroundColor Yellow
    Write-Host "Usage: .\manual-concurrency-test.ps1 -Port 8080 -ApiKey 'your-key'" -ForegroundColor Yellow
    Write-Host ""
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne 'y') {
        exit
    }
}

Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host ""

# Test 1: Verify endpoint is accessible
Write-Host "[Test 0] Verifying endpoint accessibility..." -ForegroundColor Yellow
try {
    $testResponse = Invoke-RestMethod -Uri "$BaseUrl/api/v1/system/test/concurrency?delay=1&id=connectivity-test" `
        -Method Get `
        -Headers $Headers `
        -TimeoutSec 10
    Write-Host "  ✓ Endpoint accessible" -ForegroundColor Green
    Write-Host "  Response: $($testResponse | ConvertTo-Json -Compress)" -ForegroundColor Gray
} catch {
    Write-Host "  ✗ Cannot access endpoint: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Is the server running on port $Port?" -ForegroundColor Gray
    Write-Host "  2. Do you have the 'debug' role?" -ForegroundColor Gray
    Write-Host "  3. Is your API key or session ID valid?" -ForegroundColor Gray
    exit 1
}

Write-Host ""

# Test 2: 3 concurrent 5-second requests
Write-Host "[Test 1] Testing 3 concurrent 5-second requests..." -ForegroundColor Yellow
Write-Host "  Expected: ~5 seconds (concurrent)" -ForegroundColor Gray
Write-Host "  If sequential: ~15 seconds" -ForegroundColor Gray
Write-Host ""

$testStart = Get-Date
Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Launching 3 requests..." -ForegroundColor Cyan

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
    } -ArgumentList $BaseUrl, $Headers, $requestId

    $jobs += $job
    Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Started job $requestId" -ForegroundColor Gray
}

Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Waiting for completion..." -ForegroundColor Cyan
$results = $jobs | Wait-Job -Timeout 12 | Receive-Job
$jobs | Remove-Job -Force

$testEnd = Get-Date
$duration = ($testEnd - $testStart).TotalSeconds

Write-Host ""
Write-Host "  === Results ===" -ForegroundColor Yellow
Write-Host "  Total duration: $([math]::Round($duration, 2))s " -NoNewline
if ($duration -lt 8) {
    Write-Host "✓ PASS (concurrent)" -ForegroundColor Green
} else {
    Write-Host "✗ FAIL (appears sequential)" -ForegroundColor Red
}

$successCount = @($results | Where-Object { $_.success -eq $true }).Count
Write-Host "  Successful: $successCount/3" -ForegroundColor $(if ($successCount -eq 3) { "Green" } else { "Red" })

foreach ($result in $results) {
    if ($result.success) {
        Write-Host "    ✓ $($result.requestId): $($result.actualDuration)s (Runspace: $($result.runspaceId.Substring(0,8))...)" -ForegroundColor Green
    } else {
        Write-Host "    ✗ $($result.requestId): FAILED - $($result.error)" -ForegroundColor Red
    }
}

# Check for unique runspaces
if ($successCount -gt 0) {
    $uniqueRunspaces = ($results | Where-Object { $_.success } | Select-Object -ExpandProperty runspaceId -Unique).Count
    Write-Host "  Unique runspaces: $uniqueRunspaces " -NoNewline
    if ($uniqueRunspaces -gt 1) {
        Write-Host "✓ (true parallelism)" -ForegroundColor Green
    } else {
        Write-Host "✗ (single runspace)" -ForegroundColor Red
    }
}

Write-Host ""

# Test 3: 5 concurrent 3-second requests
Write-Host "[Test 2] Testing 5 concurrent 3-second requests..." -ForegroundColor Yellow
Write-Host "  Expected: ~3 seconds (concurrent)" -ForegroundColor Gray
Write-Host "  If sequential: ~15 seconds" -ForegroundColor Gray
Write-Host ""

$testStart = Get-Date
Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Launching 5 requests..." -ForegroundColor Cyan

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
    } -ArgumentList $BaseUrl, $Headers, $requestId

    $jobs += $job
}

Write-Host "  [$(Get-Date -f 'HH:mm:ss.fff')] Waiting for completion..." -ForegroundColor Cyan
$results = $jobs | Wait-Job -Timeout 10 | Receive-Job
$jobs | Remove-Job -Force

$testEnd = Get-Date
$duration = ($testEnd - $testStart).TotalSeconds

Write-Host ""
Write-Host "  === Results ===" -ForegroundColor Yellow
Write-Host "  Total duration: $([math]::Round($duration, 2))s " -NoNewline
if ($duration -lt 6) {
    Write-Host "✓ PASS (concurrent)" -ForegroundColor Green
} else {
    Write-Host "✗ FAIL (appears sequential)" -ForegroundColor Red
}

$successCount = @($results | Where-Object { $_.success -eq $true }).Count
Write-Host "  Successful: $successCount/5" -ForegroundColor $(if ($successCount -eq 5) { "Green" } else { "Red" })

Write-Host ""

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ Endpoint accessible" -ForegroundColor Green
Write-Host "Test 1: 3 concurrent requests" -NoNewline
if ($successCount -eq 3 -and $duration -lt 8) {
    Write-Host " ✓ PASS" -ForegroundColor Green
} else {
    Write-Host " ✗ FAIL" -ForegroundColor Red
}

Write-Host ""
Write-Host "Conclusion:" -ForegroundColor Yellow
if ($successCount -gt 0 -and $duration -lt 8) {
    Write-Host "  PSWebHost is correctly configured for concurrent request handling!" -ForegroundColor Green
    Write-Host "  Multiple long-running requests execute in parallel, not sequentially." -ForegroundColor Green
} else {
    Write-Host "  PSWebHost may not be handling requests concurrently." -ForegroundColor Red
    Write-Host "  Check runspace pool configuration in WebHost.ps1" -ForegroundColor Yellow
}

Write-Host ""
