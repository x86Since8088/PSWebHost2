#Requires -Version 7

<#
.SYNOPSIS
    Test Job Submission System with PowerShell and Bearer Token

.DESCRIPTION
    Comprehensive test of the Job Submission System using Bearer token authentication.
    Tests all three execution modes (MainLoop, Runspace, BackgroundJob) and API endpoints.

.PARAMETER BaseUrl
    Base URL for the PSWebHost server (default: http://localhost:8080)

.EXAMPLE
    .\Test-JobSubmissionWithBearerToken.ps1

.EXAMPLE
    .\Test-JobSubmissionWithBearerToken.ps1 -BaseUrl "http://myserver:8080"
#>

[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== PSWebHost Job Submission Test (PowerShell + Bearer Token) ===`n" -ForegroundColor Cyan

# Load API key from config
$configPath = Join-Path $PSScriptRoot ".config\test-api-keys.json"

if (-not (Test-Path $configPath)) {
    Write-Host "Error: $configPath not found" -ForegroundColor Red
    Write-Host "Run Create-TestApiKey.ps1 first to create test API key" -ForegroundColor Yellow
    exit 1
}

$testConfig = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey = $testConfig.TestJobSubmissionKey.ApiKey

if (-not $apiKey) {
    Write-Host "Error: API key not found in config" -ForegroundColor Red
    exit 1
}

Write-Host "✓ API key loaded ($($apiKey.Substring(0, 20))...)`n" -ForegroundColor Green

# Setup headers
$headers = @{
    "Authorization" = "Bearer $apiKey"
}

$apiBase = "$BaseUrl/apps/WebHostTaskManagement/api/v1"

# Test counter
$testsPassed = 0
$testsTotal = 0

function Test-JobSubmission {
    param(
        [string]$TestName,
        [scriptblock]$TestBlock
    )

    $script:testsTotal++
    Write-Host "Test $script:testsTotal: $TestName" -ForegroundColor Cyan

    try {
        & $TestBlock
        $script:testsPassed++
        Write-Host "✓ $TestName passed`n" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "✗ $TestName failed: $($_.Exception.Message)`n" -ForegroundColor Red
        return $false
    }
}

# Test 1: Submit a simple MainLoop job
Test-JobSubmission "Submit simple MainLoop job" {
    $body = @{
        jobName = "PowerShellTestJob"
        command = "Get-Date; Write-Output 'Hello from PowerShell'; Get-Process | Select-Object -First 3"
        description = "Test job via PowerShell with Bearer token"
        executionMode = "MainLoop"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$apiBase/jobs/submit" `
        -Method POST `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body

    if (-not $response.success) {
        throw "Job submission failed: $($response.message)"
    }

    $script:mainLoopJobId = $response.jobId
    Write-Host "  Job ID: $($response.jobId)" -ForegroundColor Yellow
}

# Test 2: Wait and retrieve MainLoop job result
Test-JobSubmission "Retrieve MainLoop job result" {
    Write-Host "  Waiting 4 seconds for job execution..." -ForegroundColor Yellow
    Start-Sleep -Seconds 4

    $results = Invoke-RestMethod `
        -Uri "$apiBase/jobs/results" `
        -Headers $headers

    if (-not $results.success) {
        throw "Failed to retrieve results"
    }

    $jobResult = $results.results | Where-Object { $_.JobID -eq $script:mainLoopJobId }

    if (-not $jobResult) {
        throw "Job result not found"
    }

    Write-Host "  Job Name: $($jobResult.JobName)" -ForegroundColor White
    Write-Host "  Runtime: $($jobResult.Runtime) seconds" -ForegroundColor White
    Write-Host "  Success: $($jobResult.Success)" -ForegroundColor White
    Write-Host "`n  Output:" -ForegroundColor Cyan
    Write-Host "  $($jobResult.Output)" -ForegroundColor Gray
}

# Test 3: Submit Runspace job
Test-JobSubmission "Submit Runspace job (async)" {
    $body = @{
        jobName = "RunspaceTest"
        command = "1..5 | ForEach-Object { Start-Sleep -Milliseconds 500; Write-Output `"Step `$_`" }"
        description = "Async runspace test"
        executionMode = "Runspace"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$apiBase/jobs/submit" `
        -Method POST `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body

    if (-not $response.success) {
        throw "Runspace job submission failed"
    }

    $script:runspaceJobId = $response.jobId
    Write-Host "  Job ID: $($response.jobId)" -ForegroundColor Yellow
    Write-Host "  Note: Runspace job will complete in ~2.5 seconds (async)" -ForegroundColor Gray
}

# Test 4: Submit BackgroundJob
Test-JobSubmission "Submit Background job" {
    $body = @{
        jobName = "BackgroundJobTest"
        command = "Get-ComputerInfo | Select-Object OsName, OsVersion | ConvertTo-Json"
        description = "Background job test"
        executionMode = "BackgroundJob"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$apiBase/jobs/submit" `
        -Method POST `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body

    if (-not $response.success) {
        throw "Background job submission failed"
    }

    $script:bgJobId = $response.jobId
    Write-Host "  Job ID: $($response.jobId)" -ForegroundColor Yellow
}

# Test 5: Error handling
Test-JobSubmission "Test error capture" {
    $body = @{
        jobName = "ErrorTest"
        command = "Write-Output 'Before error'; throw 'Intentional test error'; Write-Output 'After error'"
        description = "Error handling test"
        executionMode = "MainLoop"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
        -Uri "$apiBase/jobs/submit" `
        -Method POST `
        -Headers $headers `
        -ContentType "application/json" `
        -Body $body

    $script:errorJobId = $response.jobId

    Start-Sleep -Seconds 3

    $results = Invoke-RestMethod `
        -Uri "$apiBase/jobs/results" `
        -Headers $headers

    $errorResult = $results.results | Where-Object { $_.JobID -eq $script:errorJobId }

    if (-not $errorResult) {
        throw "Error job result not found"
    }

    if ($errorResult.Success -eq $true) {
        throw "Error job should have failed but succeeded"
    }

    if ($errorResult.Output -notmatch "Intentional test error") {
        throw "Error message not captured in output"
    }

    Write-Host "  Error correctly captured: $($errorResult.Output.Substring(0, [Math]::Min(100, $errorResult.Output.Length)))..." -ForegroundColor White
}

# Test 6: Check Runspace job completion
Test-JobSubmission "Verify Runspace job completed" {
    Write-Host "  Waiting for Runspace job completion..." -ForegroundColor Yellow

    $maxWait = 10
    $elapsed = 0
    $jobCompleted = $false

    while ($elapsed -lt $maxWait) {
        Start-Sleep -Seconds 1
        $elapsed++

        $results = Invoke-RestMethod `
            -Uri "$apiBase/jobs/results" `
            -Headers $headers

        $runspaceResult = $results.results | Where-Object { $_.JobID -eq $script:runspaceJobId }

        if ($runspaceResult) {
            $jobCompleted = $true
            Write-Host "  Runspace job completed in ~$($runspaceResult.Runtime) seconds" -ForegroundColor White
            Write-Host "  Output: $($runspaceResult.Output)" -ForegroundColor Gray
            break
        }
    }

    if (-not $jobCompleted) {
        throw "Runspace job did not complete within $maxWait seconds"
    }
}

# Test 7: Get all results with pagination
Test-JobSubmission "Get results with pagination" {
    $results = Invoke-RestMethod `
        -Uri "$apiBase/jobs/results?maxResults=5" `
        -Headers $headers

    if (-not $results.success) {
        throw "Failed to get paginated results"
    }

    Write-Host "  Retrieved $($results.count) results (max 5)" -ForegroundColor White

    if ($results.count -gt 0) {
        Write-Host "  Latest job: $($results.results[0].JobName)" -ForegroundColor Gray
    }
}

# Test 8: Delete job results
Test-JobSubmission "Delete job results" {
    # Delete MainLoop job result
    $deleteResponse = Invoke-RestMethod `
        -Uri "$apiBase/jobs/results?jobId=$($script:mainLoopJobId)" `
        -Method DELETE `
        -Headers $headers

    if (-not $deleteResponse.success) {
        throw "Failed to delete job result"
    }

    Write-Host "  Deleted job: $($script:mainLoopJobId)" -ForegroundColor White

    # Verify deletion
    $results = Invoke-RestMethod `
        -Uri "$apiBase/jobs/results" `
        -Headers $headers

    $deletedJob = $results.results | Where-Object { $_.JobID -eq $script:mainLoopJobId }

    if ($deletedJob) {
        throw "Job result still exists after deletion"
    }
}

# Test 9: Invalid execution mode
Test-JobSubmission "Reject invalid execution mode" {
    $body = @{
        jobName = "InvalidModeTest"
        command = "Write-Output 'Test'"
        executionMode = "InvalidMode"
    } | ConvertTo-Json

    $failed = $false
    try {
        Invoke-RestMethod `
            -Uri "$apiBase/jobs/submit" `
            -Method POST `
            -Headers $headers `
            -ContentType "application/json" `
            -Body $body
    } catch {
        $failed = $true
        Write-Host "  Correctly rejected invalid mode" -ForegroundColor White
    }

    if (-not $failed) {
        throw "Invalid execution mode was accepted (should have failed)"
    }
}

# Test 10: Unauthorized request (no Bearer token)
Test-JobSubmission "Reject request without Bearer token" {
    $failed = $false
    try {
        Invoke-RestMethod `
            -Uri "$apiBase/jobs/results" `
            -ErrorAction Stop
    } catch {
        $failed = $true
        Write-Host "  Correctly rejected request without auth" -ForegroundColor White
    }

    if (-not $failed) {
        throw "Request without Bearer token was accepted (should have failed)"
    }
}

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Tests Passed: $testsPassed / $testsTotal" -ForegroundColor $(if ($testsPassed -eq $testsTotal) { "Green" } else { "Yellow" })

if ($testsPassed -eq $testsTotal) {
    Write-Host "`n✓ All tests passed successfully!" -ForegroundColor Green
} else {
    Write-Host "`n✗ Some tests failed" -ForegroundColor Red
    exit 1
}

# Cleanup remaining test job results
Write-Host "`nCleaning up test job results..." -ForegroundColor Yellow

$results = Invoke-RestMethod `
    -Uri "$apiBase/jobs/results" `
    -Headers $headers

$testJobIds = @($script:errorJobId, $script:runspaceJobId, $script:bgJobId) | Where-Object { $_ }

foreach ($jobId in $testJobIds) {
    try {
        Invoke-RestMethod `
            -Uri "$apiBase/jobs/results?jobId=$jobId" `
            -Method DELETE `
            -Headers $headers | Out-Null
        Write-Host "  Deleted job: $jobId" -ForegroundColor Gray
    } catch {
        Write-Host "  Failed to delete job: $jobId" -ForegroundColor DarkGray
    }
}

Write-Host "`n✓ Test complete" -ForegroundColor Green
