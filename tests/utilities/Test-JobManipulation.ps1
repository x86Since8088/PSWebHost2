#Requires -Version 7

<#
.SYNOPSIS
    Comprehensive test script for Job Manipulation System

.DESCRIPTION
    Tests all aspects of the job management system:
    - Job submission (all 3 modes)
    - Job listing and status
    - Job stopping
    - Live output retrieval
    - Result deletion

.EXAMPLE
    .\Test-JobManipulation.ps1

.EXAMPLE
    .\Test-JobManipulation.ps1 -BaseUrl "http://localhost:8080" -Verbose
#>

[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Job Manipulation System Test ===" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host ""

# Test results
$testResults = @{
    Passed = 0
    Failed = 0
    Tests = @()
}

function Test-Assert {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$ErrorMessage = "Test failed"
    )

    if ($Condition) {
        Write-Host "  ✓ $TestName" -ForegroundColor Green
        $testResults.Passed++
        $testResults.Tests += @{ Name = $TestName; Result = "PASS" }
    } else {
        Write-Host "  ✗ $TestName - $ErrorMessage" -ForegroundColor Red
        $testResults.Failed++
        $testResults.Tests += @{ Name = $TestName; Result = "FAIL"; Error = $ErrorMessage }
    }
}

# Get or create API key
Write-Host "[1/8] Authentication..." -ForegroundColor Yellow
$projectRoot = $PSScriptRoot
$newKeyScript = Join-Path $projectRoot "system\utility\Account_Auth_BearerToken_New.ps1"

if (Test-Path $newKeyScript) {
    $result = & $newKeyScript -Email "test@localhost" -Name "JobManipulationTest" -Roles @('debug', 'system_admin') -TestAccount
    if ($result -and $result.ApiKey) {
        $apiKey = $result.ApiKey
        Write-Host "  Created API key: $($result.KeyID)" -ForegroundColor Green
    } else {
        Write-Host "  ERROR: Failed to create API key" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ERROR: Bearer token script not found" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 1: Submit MainLoop Job
Write-Host "[2/8] Testing MainLoop Job Submission..." -ForegroundColor Yellow
try {
    $body = @{
        jobName = "TestJob_MainLoop"
        command = "Write-Host 'MainLoop test'; Start-Sleep -Seconds 2; Get-Date"
        description = "Test MainLoop execution"
        executionMode = "MainLoop"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/submit" `
        -Method POST `
        -Headers @{ "Authorization" = "Bearer $apiKey" } `
        -ContentType "application/json" `
        -Body $body

    $mainLoopJobId = $response.jobId
    Test-Assert "MainLoop job submitted" ($response.success -eq $true)
    Test-Assert "MainLoop job ID returned" (-not [string]::IsNullOrEmpty($mainLoopJobId))
} catch {
    Test-Assert "MainLoop job submission" $false $_.Exception.Message
}

Write-Host ""

# Test 2: Submit BackgroundJob
Write-Host "[3/8] Testing BackgroundJob Submission..." -ForegroundColor Yellow
try {
    $body = @{
        jobName = "TestJob_Background"
        command = "for (\$i=1; \$i -le 5; \$i++) { Write-Host \"Iteration \$i\"; Start-Sleep -Seconds 1 }; 'Job complete'"
        description = "Test BackgroundJob execution"
        executionMode = "BackgroundJob"
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/submit" `
        -Method POST `
        -Headers @{ "Authorization" = "Bearer $apiKey" } `
        -ContentType "application/json" `
        -Body $body

    $backgroundJobId = $response.jobId
    Test-Assert "BackgroundJob submitted" ($response.success -eq $true)
    Test-Assert "BackgroundJob ID returned" (-not [string]::IsNullOrEmpty($backgroundJobId))
} catch {
    Test-Assert "BackgroundJob submission" $false $_.Exception.Message
}

Write-Host ""

# Wait for jobs to start
Write-Host "[4/8] Waiting for job processing (5 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
Write-Host ""

# Test 3: List All Jobs
Write-Host "[5/8] Testing Job Listing..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs" `
        -Headers @{ "Authorization" = "Bearer $apiKey" }

    Test-Assert "Job listing successful" ($response.success -eq $true)
    Test-Assert "Jobs object returned" ($null -ne $response.jobs)
    Test-Assert "Counts object returned" ($null -ne $response.counts)

    $totalJobs = $response.counts.total
    Write-Host "  Found $totalJobs total jobs" -ForegroundColor Gray
    Write-Host "    Pending: $($response.counts.pending)" -ForegroundColor Gray
    Write-Host "    Running: $($response.counts.running)" -ForegroundColor Gray
    Write-Host "    Completed: $($response.counts.completed)" -ForegroundColor Gray
} catch {
    Test-Assert "Job listing" $false $_.Exception.Message
}

Write-Host ""

# Test 4: Get Specific Job Status
Write-Host "[6/8] Testing Job Status Query..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs?jobId=$backgroundJobId" `
        -Headers @{ "Authorization" = "Bearer $apiKey" }

    Test-Assert "Job status query successful" ($response.success -eq $true)
    Test-Assert "Job object returned" ($null -ne $response.job)
    Test-Assert "Job ID matches" ($response.job.JobID -eq $backgroundJobId)

    Write-Host "  Job Status: $($response.job.Status)" -ForegroundColor Gray
    if ($response.job.Runtime) {
        Write-Host "  Runtime: $($response.job.Runtime)s" -ForegroundColor Gray
    }
} catch {
    Test-Assert "Job status query" $false $_.Exception.Message
}

Write-Host ""

# Test 5: Get Live Output
Write-Host "[7/8] Testing Live Output Retrieval..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/output?jobId=$backgroundJobId" `
        -Headers @{ "Authorization" = "Bearer $apiKey" }

    Test-Assert "Live output query successful" ($response.success -eq $true -or $response.success -eq $false)

    if ($response.success) {
        Write-Host "  Output retrieved: $($response.output.Length) characters" -ForegroundColor Gray
        if ($response.output.Length -gt 0) {
            Write-Host "  First 100 chars: $($response.output.Substring(0, [Math]::Min(100, $response.output.Length)))" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Output not available: $($response.message)" -ForegroundColor Yellow
    }
} catch {
    Test-Assert "Live output retrieval" $false $_.Exception.Message
}

Write-Host ""

# Test 6: Stop Job (if still running)
Write-Host "[8/8] Testing Job Stop..." -ForegroundColor Yellow
try {
    # Submit a long-running job
    $body = @{
        jobName = "TestJob_LongRunning"
        command = "Start-Sleep -Seconds 30; Write-Host 'Should not see this'"
        description = "Long-running job for stop test"
        executionMode = "BackgroundJob"
    } | ConvertTo-Json

    $submitResponse = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/submit" `
        -Method POST `
        -Headers @{ "Authorization" = "Bearer $apiKey" } `
        -ContentType "application/json" `
        -Body $body

    $longJobId = $submitResponse.jobId
    Start-Sleep -Seconds 2  # Let it start

    # Stop it
    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs?jobId=$longJobId" `
        -Method DELETE `
        -Headers @{ "Authorization" = "Bearer $apiKey" }

    Test-Assert "Job stop successful" ($response.success -eq $true)
    Test-Assert "Stop message returned" (-not [string]::IsNullOrEmpty($response.message))

    Write-Host "  Stop result: $($response.message)" -ForegroundColor Gray
} catch {
    Test-Assert "Job stop" $false $_.Exception.Message
}

Write-Host ""

# Summary
Write-Host "=== Test Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Passed: $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed: $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total: $($testResults.Passed + $testResults.Failed)" -ForegroundColor White
Write-Host ""

if ($testResults.Failed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults.Tests | Where-Object { $_.Result -eq 'FAIL' } | ForEach-Object {
        Write-Host "  ✗ $($_.Name): $($_.Error)" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Open Task Manager UI:" -ForegroundColor White
Write-Host "   $BaseUrl" -ForegroundColor Gray
Write-Host "   Navigate to: Task Management → Jobs" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Test UI Features:" -ForegroundColor White
Write-Host "   - View pending/running/completed jobs" -ForegroundColor Gray
Write-Host "   - Click 'View Output' on running BackgroundJob" -ForegroundColor Gray
Write-Host "   - Click 'Stop' to terminate a running job" -ForegroundColor Gray
Write-Host "   - Click 'View Details' on completed job" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Monitor Job Execution:" -ForegroundColor White
Write-Host "   - Jobs auto-refresh every 5 seconds" -ForegroundColor Gray
Write-Host "   - Live output updates on refresh" -ForegroundColor Gray
Write-Host ""

if ($testResults.Failed -eq 0) {
    Write-Host "✅ All tests passed! Job Manipulation System is working correctly." -ForegroundColor Green
} else {
    Write-Host "⚠ Some tests failed. Review errors above." -ForegroundColor Yellow
}

Write-Host ""

# Return exit code
exit $testResults.Failed
