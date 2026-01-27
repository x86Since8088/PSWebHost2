#Requires -Version 7

<#
.SYNOPSIS
    Test script for memory analysis workflow in WebHostTaskManagement

.DESCRIPTION
    This script demonstrates and tests the complete workflow:
    1. Submit a recurring scheduler job (runs every 30 minutes)
    2. Submit a one-time memory analysis job
    3. Query job results
    4. View results in the UI

.EXAMPLE
    .\Test-MemoryAnalysisWorkflow.ps1

.EXAMPLE
    .\Test-MemoryAnalysisWorkflow.ps1 -SkipScheduler
#>

[CmdletBinding()]
param(
    [switch]$SkipScheduler,
    [string]$BaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Memory Analysis Workflow Test ===" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl" -ForegroundColor Gray
Write-Host ""

# Get or create authentication token
Write-Host "[1/5] Authentication..." -ForegroundColor Yellow
$projectRoot = $PSScriptRoot

# Try to get existing API key with debug role
$getKeyScript = Join-Path $projectRoot "system\utility\Account_Auth_BearerToken_Get_Enhanced.ps1"
if (Test-Path $getKeyScript) {
    $keys = & $getKeyScript | Where-Object { $_.Roles -like '*debug*' }
    if ($keys -and $keys.Count -gt 0) {
        # The Get script returns a table display, we need to use the raw API key
        # For now, skip existing keys and create new one
        # $apiKey = $keys[0].Key
        # Write-Host "  Using existing API key" -ForegroundColor Green
    }
}

# If no key, create one
if (-not $apiKey) {
    Write-Host "  No API key found. Creating test API key..." -ForegroundColor Yellow
    $newKeyScript = Join-Path $projectRoot "system\utility\Account_Auth_BearerToken_New.ps1"

    if (Test-Path $newKeyScript) {
        $result = & $newKeyScript -Email "test@localhost" -Name "MemoryAnalysisTest" -Roles @('debug', 'system_admin') -TestAccount

        if ($result -and $result.ApiKey) {
            $apiKey = $result.ApiKey
            Write-Host "  Created new API key: $($result.KeyID)" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: Failed to create API key" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  ERROR: Bearer token script not found" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Helper function to submit jobs
function Submit-Job {
    param(
        [string]$JobName,
        [string]$Command,
        [string]$Description,
        [string]$ExecutionMode = 'MainLoop'
    )

    $body = @{
        jobName = $JobName
        command = $Command
        description = $Description
        executionMode = $ExecutionMode
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/submit" `
            -Method POST `
            -Headers @{ "Authorization" = "Bearer $apiKey" } `
            -ContentType "application/json" `
            -Body $body

        return $response
    }
    catch {
        Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Submit scheduler job (runs every 30 minutes)
if (-not $SkipScheduler) {
    Write-Host "[2/5] Submitting Recurring Scheduler Job..." -ForegroundColor Yellow
    $schedulerScript = Join-Path $projectRoot "system\utility\Schedule-MemoryAnalysis.ps1"
    $schedulerCommand = "& '$schedulerScript' -IntervalMinutes 30"

    $result = Submit-Job `
        -JobName "MemoryAnalysisScheduler" `
        -Command $schedulerCommand `
        -Description "Recurring memory analysis (every 30min)" `
        -ExecutionMode "BackgroundJob"

    if ($result -and $result.success) {
        Write-Host "  Scheduler job submitted: $($result.jobId)" -ForegroundColor Green
        Write-Host "  This job will submit memory analysis every 30 minutes" -ForegroundColor Gray
    } else {
        Write-Host "  Failed to submit scheduler job" -ForegroundColor Red
    }
} else {
    Write-Host "[2/5] Skipping Scheduler Job (--SkipScheduler)" -ForegroundColor Gray
}

Write-Host ""

# Submit one-time memory analysis
Write-Host "[3/5] Submitting One-Time Memory Analysis..." -ForegroundColor Yellow
$analysisScript = Join-Path $projectRoot "system\utility\Analyze-LiveMemory.ps1"
$csvPath = Join-Path $projectRoot "PsWebHost_Data\apps\WebHostTaskManagement\JobResults\memory_analysis_test.csv"
$analysisCommand = "& '$analysisScript' -Deep -TopCount 30 -ExportPath '$csvPath'"

$result = Submit-Job `
    -JobName "MemoryAnalysis_Test" `
    -Command $analysisCommand `
    -Description "Test memory analysis" `
    -ExecutionMode "MainLoop"

if ($result -and $result.success) {
    $jobId = $result.jobId
    Write-Host "  Job submitted successfully!" -ForegroundColor Green
    Write-Host "  Job ID: $jobId" -ForegroundColor Gray
    Write-Host "  Execution Mode: $($result.executionMode)" -ForegroundColor Gray
} else {
    Write-Host "  Failed to submit job" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Wait for execution
Write-Host "[4/5] Waiting for job execution..." -ForegroundColor Yellow
Write-Host "  Jobs are processed every 2 seconds by the main loop" -ForegroundColor Gray
Write-Host "  Waiting 5 seconds..." -ForegroundColor Gray

Start-Sleep -Seconds 5

Write-Host ""

# Query results
Write-Host "[5/5] Querying Job Results..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/results?maxResults=10" `
        -Headers @{ "Authorization" = "Bearer $apiKey" }

    if ($response.success) {
        Write-Host "  Found $($response.count) results" -ForegroundColor Green
        Write-Host ""

        # Show most recent results
        $recentResults = $response.results | Sort-Object DateCompleted -Descending | Select-Object -First 5

        foreach ($result in $recentResults) {
            $status = if ($result.Success) { "SUCCESS" } else { "FAILED" }
            $statusColor = if ($result.Success) { "Green" } else { "Red" }

            Write-Host "  Job: $($result.JobName)" -ForegroundColor White
            Write-Host "    Status: $status" -ForegroundColor $statusColor
            Write-Host "    Started: $($result.DateStarted)" -ForegroundColor Gray
            Write-Host "    Runtime: $([math]::Round($result.Runtime, 3))s" -ForegroundColor Gray

            # Show first 3 lines of output
            if ($result.Output) {
                $lines = $result.Output -split "`n" | Select-Object -First 3
                Write-Host "    Output preview:" -ForegroundColor Gray
                foreach ($line in $lines) {
                    Write-Host "      $line" -ForegroundColor DarkGray
                }
            }

            Write-Host ""
        }

        # Find our specific job
        $ourResult = $response.results | Where-Object { $_.JobID -eq $jobId }
        if ($ourResult) {
            Write-Host "  ✓ Found result for test job: $jobId" -ForegroundColor Green

            if ($ourResult.Success) {
                Write-Host "  ✓ Job completed successfully!" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Job failed" -ForegroundColor Red
            }
        } else {
            Write-Host "  ⚠ Result not found yet (may still be executing)" -ForegroundColor Yellow
            Write-Host "  Try querying again in a few seconds" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Failed to get results" -ForegroundColor Red
    }
}
catch {
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. View results in WebHostTaskManagement UI:" -ForegroundColor White
Write-Host "   $BaseUrl" -ForegroundColor Gray
Write-Host "   Navigate to: Task Management → Job Results" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Query results via API:" -ForegroundColor White
Write-Host "   curl -H 'Authorization: Bearer $apiKey' \\" -ForegroundColor Gray
Write-Host "        $BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/results" -ForegroundColor Gray
Write-Host ""
Write-Host "3. View specific job result:" -ForegroundColor White
Write-Host "   Job ID: $jobId" -ForegroundColor Gray
Write-Host ""

if (-not $SkipScheduler) {
    Write-Host "4. Scheduler is running:" -ForegroundColor White
    Write-Host "   A new memory analysis will be submitted every 30 minutes" -ForegroundColor Gray
    Write-Host "   Check Job Results view to see recurring analysis" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host ""
