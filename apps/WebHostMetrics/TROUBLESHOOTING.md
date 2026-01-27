# WebHostMetrics Troubleshooting Guide

**Date**: 2026-01-21
**Status**: Job starts but doesn't collect metrics

## Summary

All fixes have been applied successfully:
1. ✅ Fixed "Metrics property not found" error
2. ✅ Added Write-PSWebHostLog to job errors
3. ✅ Consolidated modules to `apps/WebHostMetrics/modules/`
4. ✅ Fixed module import paths
5. ✅ Fixed DataRoot path issues
6. ✅ Job initializes and starts successfully

**Current Issue**: The metrics collection job starts (Job ID 1) but doesn't produce CSV files or debug output.

## How to Diagnose from Server Console

Run these commands from your PSWebHost server PowerShell console (where `$Global:PSWebServer` exists):

### 1. Check if Job Exists and is Running

```powershell
Get-Job | Where-Object { $_.Name -like '*Metrics*' } | Format-List Id, Name, State, HasMoreData
```

**Expected**: You should see `PSWebHost_MetricsCollection` job with `State: Running`

### 2. Check Job Output

```powershell
$job = Get-Job -Name "PSWebHost_MetricsCollection"
Receive-Job -Job $job -Keep 2>&1 | Select-Object -Last 50
```

**Expected Output**: You should see debug messages like:
```
[MetricsJob] Job starting...
[MetricsJob] ProjectRoot: C:\SC\PsWebHost
[MetricsJob] Module imported successfully
[MetricsJob] Entering main loop...
[MetricsJob] Iteration 1 - Still running...
[MetricsJob] Executing Invoke-MetricJobMaintenance...
```

**If you see NO output**: The job scriptblock isn't executing. This could be because:
- The scriptblock parameters are wrong
- The job crashed on startup
- PowerShell version issue

### 3. Check Metrics Object

```powershell
$Global:PSWebServer.Metrics.Current | Format-List Timestamp, Hostname
$Global:PSWebServer.Metrics.Samples.Count
$Global:PSWebServer.Metrics.JobState | Format-List
```

**Expected**:
- `Timestamp` should have a recent time
- `Samples.Count` should be growing (check multiple times)
- `JobState.LastCollection` should update every 5 seconds

### 4. Check for Errors

```powershell
$Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 5 | Format-List
```

### 5. Check Child Job Errors

```powershell
$job = Get-Job -Name "PSWebHost_MetricsCollection"
$job.ChildJobs[0].Error | ForEach-Object { Write-Host $_ -ForegroundColor Red }
$job.ChildJobs[0].Warning | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
```

### 6. Manually Test Metrics Collection

```powershell
# Test if the function works outside the job
Import-Module "C:\SC\PsWebHost\apps\WebHostMetrics\modules\PSWebHost_Metrics\PSWebHost_Metrics.psm1" -Force
$snapshot = Get-SystemMetricsSnapshot
$snapshot | Format-List

# This should return current metrics
Get-CurrentMetrics
```

## Common Issues and Solutions

### Issue 1: Job Scriptblock Not Executing

**Symptoms**: Job shows `State: Running` but no output

**Possible Causes**:
- Parameters passed to Start-Job are null/invalid
- Job crashed immediately on startup
- Module import failed in job scope

**Solution**: Check the job's child job for errors:
```powershell
$job = Get-Job -Name "PSWebHost_MetricsCollection"
$job.ChildJobs[0] | Format-List *
```

### Issue 2: Module Not Found in Job

**Symptoms**: Job output shows "module not found" error

**Solution**: The job should use explicit module path. Check `app_init.ps1` line 54-62.

### Issue 3: $Global:PSWebServer Not Available in Job

**Symptoms**: Error about `$Global:PSWebServer` being null

**Solution**: The entire `$Global:PSWebServer.Metrics` object is passed to the job and reattached in job scope (app_init.ps1 lines 42-49).

### Issue 4: CSV Directory Doesn't Exist

**Symptoms**: No CSV files created

**Check**:
```powershell
$csvDir = "C:\SC\PsWebHost\PsWebHost_Data\metrics"
Test-Path $csvDir
# If false, create it:
New-Item -Path $csvDir -ItemType Directory -Force
```

## Manual Metrics Collection Test

If the job isn't working, you can manually test metrics collection:

```powershell
# 1. Load the module
Import-Module "C:\SC\PsWebHost\apps\WebHostMetrics\modules\PSWebHost_Metrics\PSWebHost_Metrics.psm1" -Force

# 2. Initialize if needed
if (-not $Global:PSWebServer.Metrics) {
    Initialize-PSWebMetrics
}

# 3. Manually collect a snapshot
$snapshot = Get-SystemMetricsSnapshot
Update-CurrentMetrics -Snapshot $snapshot
Add-MetricsSample -Snapshot $snapshot

# 4. Check the results
$Global:PSWebServer.Metrics.Current
$Global:PSWebServer.Metrics.Samples.Count

# 5. Try writing CSV (this should create files after 1 minute)
Write-MetricsToInterimCsv -Force
```

Then check for CSV files:
```powershell
Get-ChildItem "C:\SC\PsWebHost\PsWebHost_Data\metrics" -Filter "*_2026-*.csv" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5
```

## Restart Metrics Collection

To restart the metrics collection job:

```powershell
# 1. Stop the current job
if ($Global:PSWebServer.MetricsJob) {
    $Global:PSWebServer.Metrics.JobState.ShouldStop = $true
    Start-Sleep -Seconds 6
    Stop-Job -Job $Global:PSWebServer.MetricsJob -ErrorAction SilentlyContinue
    Remove-Job -Job $Global:PSWebServer.MetricsJob -Force -ErrorAction SilentlyContinue
}

# 2. Re-run app initialization
. "C:\SC\PsWebHost\apps\WebHostMetrics\app_init.ps1" `
    -PSWebServer $Global:PSWebServer `
    -AppRoot "C:\SC\PsWebHost\apps\WebHostMetrics"

# 3. Check if it started
Get-Job -Name "PSWebHost_MetricsCollection"
```

## Expected Behavior

When working correctly, you should see:

1. **Every 5 seconds**: New sample added to `$Global:PSWebServer.Metrics.Samples`
2. **Every 1 minute** (at :00 seconds): New CSV files created in `PsWebHost_Data/metrics/`
   - `Perf_CPUCore_YYYY-MM-DD_HH-MM-00.csv`
   - `Perf_MemoryUsage_YYYY-MM-DD_HH-MM-00.csv`
   - `Perf_DiskIO_YYYY-MM-DD_HH-MM-00.csv` (if disk activity)
   - `Network_YYYY-MM-DD_HH-MM-00.csv` (if network activity)

3. **Job output** (every 12 iterations = 1 minute):
   ```
   [MetricsJob] Iteration 13 - Still running...
   [MetricsJob] Executing Invoke-MetricJobMaintenance...
   [MetricsJob] Maintenance completed successfully
   ```

## Contact Points

If you've run all diagnostics and metrics still aren't collecting:

1. Share the output of the diagnostic commands above
2. Check if there's a PowerShell version compatibility issue
3. Verify Windows Performance Counters are accessible:
   ```powershell
   Get-Counter '\Processor(_Total)\% Processor Time'
   Get-Counter '\Memory\Available MBytes'
   ```

## Files Modified

All fixes are in these files:
- `apps/WebHostMetrics/app_init.ps1` - Job initialization with debug output
- `apps/WebHostMetrics/modules/PSWebHost_Metrics/PSWebHost_Metrics.psm1` - Module functions
- Deleted: `modules/PSWebHost_Metrics/` - Consolidated into app

## Next Steps

Once you run the diagnostics above, we'll know exactly why the job isn't producing output and can fix the specific issue.
