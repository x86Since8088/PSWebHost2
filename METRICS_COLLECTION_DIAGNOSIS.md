# Metrics Collection System Diagnosis

## Problem Identified

The Server Load card (server-heatmap) shows **no data** because the metrics collection system has stopped collecting data.

## Evidence

### 1. API Responses Show Empty Data
```
data: {}
endTime: "2026-01-16T13:05:17.6783962-06:00"
granularity: "5s"
startTime: "2026-01-16T13:04:17.5740000-06:00"
status: "success"
```

### 2. No Recent Metrics CSV Files

Latest metrics files are from **January 8, 2026 23:59** (8 days old):
```
-rw-r--r--  673 Jan  8 23:59 Network_2026-01-08_23-59-00.csv
-rw-r--r--  582 Jan  8 23:59 Perf_CPUCore_2026-01-08_23-59-00.csv
-rw-r--r--  117 Jan  8 23:59 Perf_MemoryUsage_2026-01-08_23-59-00.csv
```

### 3. API Endpoint Filters by Date

The `/api/v1/metrics?action=realtime` endpoint:
- Filters CSV files where `$fileTime -ge $starting`
- Client requests data from `starting=2026-01-16T19:03:57.509Z` (today)
- No files match because newest is from Jan 8
- Returns `data: {}` (empty)

## Root Cause

**The PowerShell metrics collection background job is not running.**

The job should be:
- **Name**: `PSWebHost_MetricsCollection`
- **Function**: Collect system metrics every 5 seconds
- **Output**: Write CSV files to `PsWebHost_Data/metrics/`
- **Started by**: `system/init.ps1` line 798

## How the Metrics System Works

### Collection Flow

1. **Initialization** (`system/init.ps1:779`):
   ```powershell
   Import-Module PSWebHost_Metrics -Force
   Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30
   ```

2. **Background Job Started** (`system/init.ps1:798`):
   ```powershell
   $Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock { ... }
   ```

3. **Job Loop** (runs every 5 seconds):
   - Calls `Get-SystemMetricsSnapshot`
   - Collects CPU, memory, disk, network stats
   - Writes to CSV files in `PsWebHost_Data/metrics/`
   - Files named: `Perf_CPUCore_YYYY-MM-DD_HH-MM-SS.csv`

4. **API Reads CSV Files** (`routes/api/v1/metrics/get.ps1:76-146`):
   - Scans `PsWebHost_Data/metrics/*.csv`
   - Filters by timestamp in filename
   - Returns matching CSV data as JSON

### Why the Job Stopped

Possible reasons:
1. **Server was restarted** - Jobs don't survive restarts
2. **Job crashed** - Error in collection logic
3. **Job was manually stopped** - Someone ran `Stop-Job`
4. **Module failed to load** - `PSWebHost_Metrics` module error

## Diagnosis Commands

### Check if Metrics Job is Running

```powershell
# Check all background jobs
Get-Job

# Check specifically for metrics job
Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue

# Check global variable
$Global:PSWebServer.MetricsJob

# Check job state
$Global:PSWebServer.Metrics.JobState
```

### Check Recent CSV Files

```powershell
# List most recent metrics files
Get-ChildItem -Path "PsWebHost_Data/metrics/*.csv" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 Name, LastWriteTime, Length
```

### Check Module is Loaded

```powershell
# Check if module is available
Get-Module PSWebHost_Metrics -ListAvailable

# Check if module is loaded
Get-Module PSWebHost_Metrics

# Check module functions
Get-Command -Module PSWebHost_Metrics
```

## Fix: Restart Metrics Collection

### Option 1: Restart PSWebHost Server (Recommended)

This will reinitialize the entire system including metrics:

```powershell
# Stop server
# Restart server (it will run system/init.ps1 automatically)
```

### Option 2: Manually Restart Metrics Job

If you don't want to restart the entire server:

```powershell
# Stop existing job (if any)
if ($Global:PSWebServer.MetricsJob) {
    Stop-Job -Job $Global:PSWebServer.MetricsJob -ErrorAction SilentlyContinue
    Remove-Job -Job $Global:PSWebServer.MetricsJob -Force -ErrorAction SilentlyContinue
}

# Reinitialize metrics system
Import-Module PSWebHost_Metrics -Force
Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30

# Set stop flag to false
if (-not $Global:PSWebServer.Metrics.JobState) {
    $Global:PSWebServer.Metrics.JobState = [hashtable]::Synchronized(@{
        ShouldStop = $false
        IsExecuting = $false
    })
} else {
    $Global:PSWebServer.Metrics.JobState.ShouldStop = $false
}

# Start the job
$modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules"
$Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock {
    param($MetricsState, $ModulePath)

    Import-Module (Join-Path $ModulePath "PSWebHost_Metrics") -Force -ErrorAction Stop

    while (-not $MetricsState.ShouldStop) {
        try {
            if ($MetricsState.IsExecuting) {
                Start-Sleep -Seconds 1
                continue
            }

            $MetricsState.IsExecuting = $true

            # Collect metrics
            $snapshot = Get-SystemMetricsSnapshot
            if ($snapshot) {
                Update-MetricsStorage -Snapshot $snapshot
            }

            $MetricsState.IsExecuting = $false
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Error "Metrics collection error: $_"
            $MetricsState.IsExecuting = $false
            Start-Sleep -Seconds 5
        }
    }
} -ArgumentList $Global:PSWebServer.Metrics.JobState, $modulePath

Write-Host "Metrics collection job started: $($Global:PSWebServer.MetricsJob.Name)" -ForegroundColor Green
```

### Option 3: Create a Restart Script

Save this as `system/utility/Restart-MetricsCollection.ps1`:

```powershell
<#
.SYNOPSIS
    Restarts the PSWebHost metrics collection job
.DESCRIPTION
    Stops any existing metrics collection job and starts a new one
#>

param(
    [switch]$Force
)

Write-Host "`n=== Metrics Collection Restart ===" -ForegroundColor Cyan

# Check current state
Write-Host "`nChecking current state..."
$existingJob = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue

if ($existingJob) {
    Write-Host "  Existing job found: State=$($existingJob.State)" -ForegroundColor Yellow

    if (-not $Force) {
        Write-Host "  Use -Force to restart the running job" -ForegroundColor Red
        return
    }

    Write-Host "  Stopping existing job..."
    Stop-Job -Job $existingJob -ErrorAction SilentlyContinue
    Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Existing job stopped" -ForegroundColor Green
} else {
    Write-Host "  No existing job found" -ForegroundColor Gray
}

# Import module
Write-Host "`nInitializing metrics module..."
try {
    Import-Module PSWebHost_Metrics -Force -ErrorAction Stop
    Write-Host "  ✓ Module loaded" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to load module: $_" -ForegroundColor Red
    return
}

# Initialize metrics storage
Write-Host "`nInitializing metrics storage..."
try {
    Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30
    Write-Host "  ✓ Storage initialized" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Failed to initialize: $_" -ForegroundColor Red
    return
}

# Reset job state
if (-not $Global:PSWebServer.Metrics.JobState) {
    $Global:PSWebServer.Metrics.JobState = [hashtable]::Synchronized(@{
        ShouldStop = $false
        IsExecuting = $false
    })
} else {
    $Global:PSWebServer.Metrics.JobState.ShouldStop = $false
    $Global:PSWebServer.Metrics.JobState.IsExecuting = $false
}

# Start job
Write-Host "`nStarting metrics collection job..."
$modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules"

$Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock {
    param($MetricsState, $ModulePath)

    Import-Module (Join-Path $ModulePath "PSWebHost_Metrics") -Force -ErrorAction Stop

    while (-not $MetricsState.ShouldStop) {
        try {
            if ($MetricsState.IsExecuting) {
                Start-Sleep -Seconds 1
                continue
            }

            $MetricsState.IsExecuting = $true

            # Collect metrics
            $snapshot = Get-SystemMetricsSnapshot
            if ($snapshot) {
                Update-MetricsStorage -Snapshot $snapshot
            }

            $MetricsState.IsExecuting = $false
            Start-Sleep -Seconds 5
        }
        catch {
            Write-Error "Metrics collection error: $_"
            $MetricsState.IsExecuting = $false
            Start-Sleep -Seconds 5
        }
    }
} -ArgumentList $Global:PSWebServer.Metrics.JobState, $modulePath

# Verify job started
Start-Sleep -Seconds 2
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue

if ($job -and $job.State -eq 'Running') {
    Write-Host "  ✓ Job started successfully" -ForegroundColor Green
    Write-Host "    Job ID: $($job.Id)" -ForegroundColor Gray
    Write-Host "    State: $($job.State)" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Job failed to start" -ForegroundColor Red
    if ($job) {
        Write-Host "    State: $($job.State)" -ForegroundColor Red
    }
}

# Check for errors
Start-Sleep -Seconds 5
$jobOutput = Receive-Job -Job $job -ErrorAction SilentlyContinue
if ($jobOutput) {
    Write-Host "`n  Job output:" -ForegroundColor Yellow
    $jobOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}

Write-Host "`n=== Restart Complete ===" -ForegroundColor Cyan
Write-Host "Wait 10 seconds and check for new CSV files in PsWebHost_Data/metrics/`n" -ForegroundColor Yellow
```

## Verification

After restarting, verify metrics are being collected:

### 1. Check Job is Running

```powershell
Get-Job -Name "PSWebHost_MetricsCollection"
# Should show State: Running
```

### 2. Wait 10 Seconds, Check for New Files

```powershell
Get-ChildItem -Path "PsWebHost_Data/metrics/*.csv" |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-1) } |
    Sort-Object LastWriteTime -Descending
```

Should show new files like:
```
Perf_CPUCore_2026-01-16_13-15-00.csv
Perf_MemoryUsage_2026-01-16_13-15-00.csv
Network_2026-01-16_13-15-00.csv
```

### 3. Check API Returns Data

```powershell
Invoke-RestMethod -Uri "http://localhost:8080/api/v1/metrics?action=realtime&metric=cpu" |
    ConvertTo-Json -Depth 5
```

Should show non-empty `data` property.

### 4. Refresh Browser

Hard refresh the server-heatmap card (Ctrl+F5), wait 10 seconds, and the graph should start showing data.

## Prevention

### Monitor Metrics Job Health

Create a monitoring endpoint or add to server startup checks:

```powershell
# Add to health check endpoint
$metricsJobHealthy = $false
$job = Get-Job -Name "PSWebHost_MetricsCollection" -ErrorAction SilentlyContinue

if ($job -and $job.State -eq 'Running') {
    # Check if job is actually collecting (files created recently)
    $recentFiles = Get-ChildItem -Path "PsWebHost_Data/metrics/*.csv" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) }

    if ($recentFiles) {
        $metricsJobHealthy = $true
    }
}

@{
    metricsCollection = @{
        healthy = $metricsJobHealthy
        jobState = $job?.State
        lastFile = (Get-ChildItem -Path "PsWebHost_Data/metrics/*.csv" |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1).LastWriteTime
    }
}
```

### Auto-Restart on Failure

Consider adding a watchdog timer to `system/init.ps1` that restarts the job if it fails.

## Summary

**Problem**: Metrics collection job stopped on Jan 8, no new data collected
**Impact**: Server load card shows empty graphs
**Fix**: Restart the PSWebHost server or manually restart the metrics job
**Verification**: Check for new CSV files in `PsWebHost_Data/metrics/` after 10 seconds

**Next Steps**:
1. Restart PSWebHost server
2. Verify metrics job is running: `Get-Job -Name "PSWebHost_MetricsCollection"`
3. Wait 10-15 seconds for new CSV files
4. Refresh browser hard (Ctrl+F5)
5. Server load card should show data
