# Debug Metrics Job
# Run this from the PSWebHost server console

Write-Host "=== Debugging Metrics Collection Job ===" -ForegroundColor Cyan

if (-not $Global:PSWebServer.MetricsJob) {
    Write-Host "No metrics job found!" -ForegroundColor Red
    exit
}

$job = $Global:PSWebServer.MetricsJob

Write-Host "`nJob Details:" -ForegroundColor Yellow
$job | Format-List Id, Name, State, HasMoreData, Location

Write-Host "`nReceiving ALL job output (this will clear the buffer):" -ForegroundColor Yellow
$output = Receive-Job -Job $job 2>&1
if ($output) {
    $output | ForEach-Object {
        if ($_ -match 'error|warning|exception') {
            Write-Host $_ -ForegroundColor Red
        } else {
            Write-Host $_
        }
    }
} else {
    Write-Host "(No output received)" -ForegroundColor Gray
}

Write-Host "`nChecking job child jobs for errors:" -ForegroundColor Yellow
foreach ($childJob in $job.ChildJobs) {
    Write-Host "  Child Job State: $($childJob.State)" -ForegroundColor Cyan
    if ($childJob.Error.Count -gt 0) {
        Write-Host "  Errors found:" -ForegroundColor Red
        $childJob.Error | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  No errors in child job" -ForegroundColor Green
    }

    if ($childJob.Warning.Count -gt 0) {
        Write-Host "  Warnings found:" -ForegroundColor Yellow
        $childJob.Warning | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Yellow
        }
    }
}

Write-Host "`nChecking Metrics JobState:" -ForegroundColor Yellow
$Global:PSWebServer.Metrics.JobState | Format-List IsExecuting, ShouldStop, LastCollection, ExecutionStartTime

Write-Host "`nWaiting 6 seconds to see if job produces new output..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

$newOutput = Receive-Job -Job $job 2>&1
if ($newOutput) {
    Write-Host "New output received:" -ForegroundColor Green
    $newOutput | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "No new output - job may not be executing" -ForegroundColor Red
}

Write-Host "`n=== End Debug ===" -ForegroundColor Cyan
