#Requires -Version 7

# Test script to start CollectMetrics job while server is running
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Testing CollectMetrics Job Start" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import the module directly since the server has it loaded
$modulePath = Join-Path $PSScriptRoot "modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1"
Import-Module $modulePath -DisableNameChecking -Force

Write-Host "[1] Checking if job system is initialized..." -ForegroundColor Yellow
if (-not $Global:PSWebServer.Jobs) {
    Write-Host "Job system not initialized. This script should be run from the server context." -ForegroundColor Red
    exit 1
}

Write-Host "    Job system is initialized" -ForegroundColor Green
Write-Host "    Catalog contains: $($Global:PSWebServer.Jobs.Catalog.Count) jobs" -ForegroundColor Gray
Write-Host "    Command queue count: $($Global:PSWebServer.Jobs.CommandQueue.Count)" -ForegroundColor Gray
Write-Host ""

Write-Host "[2] Listing discovered jobs..." -ForegroundColor Yellow
foreach ($jobKey in $Global:PSWebServer.Jobs.Catalog.Keys) {
    $job = $Global:PSWebServer.Jobs.Catalog[$jobKey]
    Write-Host "    - $jobKey" -ForegroundColor Gray
    Write-Host "      Name: $($job.Name)" -ForegroundColor DarkGray
    Write-Host "      Description: $($job.Description)" -ForegroundColor DarkGray
}
Write-Host ""

Write-Host "[3] Starting CollectMetrics job..." -ForegroundColor Yellow
$variables = @{
    Interval = '15'
}

try {
    $result = Start-PSWebHostJob -JobID "WebHostMetrics/CollectMetrics" -UserID "testuser" -SessionID "test-session" -Variables $variables -Roles @('admin')

    Write-Host "    Job queued successfully!" -ForegroundColor Green
    Write-Host "    ExecutionID: $($result.ExecutionID)" -ForegroundColor Gray
    Write-Host "    Status: $($result.Status)" -ForegroundColor Gray
    Write-Host ""

    Write-Host "[4] Processing command queue..." -ForegroundColor Yellow
    $processed = Process-PSWebHostJobCommandQueue
    Write-Host "    Processed $processed command(s)" -ForegroundColor Green
    Write-Host ""

    Write-Host "[5] Checking running jobs..." -ForegroundColor Yellow
    $runningJobs = Get-PSWebHostRunningJobs -UserID "testuser"
    if ($runningJobs.Count -eq 0) {
        Write-Host "    No running jobs found" -ForegroundColor Yellow
    } else {
        foreach ($job in $runningJobs) {
            Write-Host "    - $($job.JobID)" -ForegroundColor Gray
            Write-Host "      ExecutionID: $($job.ExecutionID)" -ForegroundColor DarkGray
            Write-Host "      Started: $($job.StartTime)" -ForegroundColor DarkGray
            Write-Host "      PSJobID: $($job.PSJobID)" -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    Write-Host "[6] Getting job status..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    $status = Get-PSWebHostJobStatus -ExecutionID $result.ExecutionID -UserID "testuser"
    if ($status) {
        Write-Host "    Status: $($status.Status)" -ForegroundColor Gray
        Write-Host "    JobID: $($status.JobID)" -ForegroundColor Gray
        Write-Host "    StartTime: $($status.StartTime)" -ForegroundColor Gray
    } else {
        Write-Host "    Status not available yet" -ForegroundColor Yellow
    }
    Write-Host ""

    Write-Host "[7] Waiting 10 seconds to let job collect metrics..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10

    Write-Host "[8] Stopping the job..." -ForegroundColor Yellow
    $stopResult = Stop-PSWebHostJob -JobID "WebHostMetrics/CollectMetrics" -UserID "testuser" -Roles @('admin')
    Write-Host "    Stop command queued" -ForegroundColor Green

    $processed = Process-PSWebHostJobCommandQueue
    Write-Host "    Processed $processed command(s)" -ForegroundColor Green
    Write-Host ""

    Write-Host "[9] Final status check..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    $finalStatus = Get-PSWebHostJobStatus -ExecutionID $result.ExecutionID -UserID "testuser"
    if ($finalStatus) {
        Write-Host "    Status: $($finalStatus.Status)" -ForegroundColor Gray
        if ($finalStatus.EndTime) {
            Write-Host "    EndTime: $($finalStatus.EndTime)" -ForegroundColor Gray
        }
        if ($finalStatus.Output) {
            Write-Host "    Output (first 500 chars):" -ForegroundColor Gray
            Write-Host "    $($finalStatus.Output.Substring(0, [Math]::Min(500, $finalStatus.Output.Length)))" -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Test completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}
catch {
    Write-Host "    Error: $_" -ForegroundColor Red
    Write-Host ""
    throw
}
