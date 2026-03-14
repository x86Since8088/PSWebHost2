# Check Server State - Run this from the PSWebHost server console
# This script checks if metrics collection is working

Write-Host "`n=== PSWebHost Server State Check ===" -ForegroundColor Cyan

# Check if we're in a server session
if (-not $Global:PSWebServer) {
    Write-Host "ERROR: This script must be run from within the PSWebHost server session" -ForegroundColor Red
    Write-Host "The `$Global:PSWebServer object does not exist" -ForegroundColor Red
    exit 1
}

Write-Host "`n1. Server is running" -ForegroundColor Green
Write-Host "   Project Root: $($Global:PSWebServer.Project_Root.Path)"

# Check WebHostMetrics app
Write-Host "`n2. WebHostMetrics App Status:" -ForegroundColor Yellow
if ($Global:PSWebServer.ContainsKey('WebHostMetrics')) {
    Write-Host "   ✓ App is loaded" -ForegroundColor Green
    $Global:PSWebServer.WebHostMetrics | Format-List
} else {
    Write-Host "   ✗ App is NOT loaded" -ForegroundColor Red
    Write-Host "   This means app_init.ps1 may have failed or not run" -ForegroundColor Yellow
}

# Check Metrics object
Write-Host "`n3. Metrics Object:" -ForegroundColor Yellow
if ($Global:PSWebServer.ContainsKey('Metrics')) {
    Write-Host "   ✓ Metrics object exists" -ForegroundColor Green
    Write-Host "   Current timestamp: $($Global:PSWebServer.Metrics.Current.Timestamp)"
    Write-Host "   Hostname: $($Global:PSWebServer.Metrics.Current.Hostname)"
    Write-Host "   Sample count: $($Global:PSWebServer.Metrics.Samples.Count)"
    Write-Host "   Last collection: $($Global:PSWebServer.Metrics.JobState.LastCollection)"
} else {
    Write-Host "   ✗ Metrics object does NOT exist" -ForegroundColor Red
}

# Check MetricsJob
Write-Host "`n4. Metrics Collection Job:" -ForegroundColor Yellow
if ($Global:PSWebServer.ContainsKey('MetricsJob') -and $Global:PSWebServer.MetricsJob) {
    Write-Host "   ✓ Job exists" -ForegroundColor Green
    $job = $Global:PSWebServer.MetricsJob
    Write-Host "   Job ID: $($job.Id)"
    Write-Host "   Job Name: $($job.Name)"
    Write-Host "   Job State: $($job.State)"
    Write-Host "   Has Data: $($job.HasMoreData)"

    if ($job.State -eq 'Failed') {
        Write-Host "   Job FAILED - checking error:" -ForegroundColor Red
        $job.ChildJobs[0].Error | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
    }

    Write-Host "`n   Recent job output:" -ForegroundColor Cyan
    $output = Receive-Job -Job $job -Keep 2>&1
    if ($output) {
        $output | Select-Object -Last 15 | ForEach-Object {
            if ($_ -match 'error|warning|failed') {
                Write-Host "   $_" -ForegroundColor Red
            } else {
                Write-Host "   $_"
            }
        }
    } else {
        Write-Host "   (No output)" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✗ Job does NOT exist" -ForegroundColor Red

    Write-Host "`n   All jobs in session:" -ForegroundColor Cyan
    $allJobs = Get-Job
    if ($allJobs) {
        $allJobs | Format-Table Id, Name, State -AutoSize
    } else {
        Write-Host "   (No jobs found)" -ForegroundColor Gray
    }
}

# Check for errors
Write-Host "`n5. Error Check:" -ForegroundColor Yellow
if ($Global:PSWebServer.Metrics -and $Global:PSWebServer.Metrics.JobState.Errors.Count -gt 0) {
    Write-Host "   Found $($Global:PSWebServer.Metrics.JobState.Errors.Count) errors" -ForegroundColor Red
    $Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 5 | ForEach-Object {
        Write-Host "   [$($_.Timestamp)] $($_.Message)" -ForegroundColor Red
        if ($_.StackTrace) {
            Write-Host "     Stack: $($_.StackTrace)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "   ✓ No errors in JobState" -ForegroundColor Green
}

# Check module
Write-Host "`n6. PSWebHost_Metrics Module:" -ForegroundColor Yellow
$module = Get-Module PSWebHost_Metrics
if ($module) {
    Write-Host "   ✓ Module is loaded" -ForegroundColor Green
    Write-Host "   Path: $($module.Path)"
} else {
    Write-Host "   ✗ Module is NOT loaded" -ForegroundColor Red
}

# Check CSV files
Write-Host "`n7. CSV File Check:" -ForegroundColor Yellow
$csvDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\metrics"
if (Test-Path $csvDir) {
    $files = Get-ChildItem $csvDir | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    if ($files) {
        Write-Host "   CSV directory exists: $csvDir" -ForegroundColor Green
        Write-Host "   Most recent files:" -ForegroundColor Cyan
        $files | ForEach-Object {
            $age = ((Get-Date) - $_.LastWriteTime).TotalMinutes
            $ageStr = if ($age -lt 60) { "$([int]$age)m ago" } else { "$([int]($age/60))h ago" }

            if ($age -lt 5) {
                Write-Host "   ✓ $($_.Name) - $($ageStr)" -ForegroundColor Green
            } else {
                Write-Host "   ✗ $($_.Name) - $($ageStr)" -ForegroundColor Yellow
            }
        }

        $newest = $files[0]
        $ageMinutes = ((Get-Date) - $newest.LastWriteTime).TotalMinutes
        if ($ageMinutes -lt 5) {
            Write-Host "`n   ✓ Metrics are being collected! (file is $([int]$ageMinutes) min old)" -ForegroundColor Green
        } else {
            Write-Host "`n   ✗ Metrics collection appears STOPPED (newest file is $([int]$ageMinutes) min old)" -ForegroundColor Red
        }
    } else {
        Write-Host "   Directory exists but contains no files" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ✗ CSV directory does NOT exist: $csvDir" -ForegroundColor Red
}

Write-Host "`n=== End Check ===" -ForegroundColor Cyan
Write-Host ""
