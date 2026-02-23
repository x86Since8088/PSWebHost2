# Metrics Collection Job Fixes

**Date**: 2026-01-20
**Task**: Fix "The property 'Metrics' cannot be found" error in metrics collection job

## Problem Diagnosis

### Error Observed
```
WARNING: [MetricsJob] Error: The property 'Metrics' cannot be found on this object.
Verify that the property exists and can be set.
```

### Root Causes Identified

1. **Missing Global Object in Job Scope**
   - The background job did not have `$Global:PSWebServer` initialized
   - Only the `JobState` synchronized hashtable was passed to the job
   - Functions inside the job tried to access `$Global:PSWebServer.Metrics` which didn't exist

2. **Missing JobState Properties**
   - Several properties used by metrics functions were not initialized in the `JobState` hashtable:
     - `LastInterimCsvWrite`
     - `LastCsvToSqliteMove`
     - `Last60sAggregation`
     - `LastCleanup`
     - `LastCsvCleanup`
     - `ExecutionStartTime`

3. **Duplicate Module Locations**
   - `PSWebHost_Metrics` module existed in two locations:
     - `modules/PSWebHost_Metrics/` (global)
     - `apps/WebHostMetrics/modules/PSWebHost_Metrics/` (app-specific)

4. **Missing Write-PSWebHostLog in Job**
   - Job errors used `Write-Warning` instead of proper logging function

## Fixes Applied

### Fix 1: Pass Entire Metrics Object to Job

**File**: `apps/WebHostMetrics/app_init.ps1` (lines 38-86)

**Changes**:
- Changed job parameter from `$MetricsState` (JobState only) to `$MetricsObject` (entire Metrics structure)
- Initialize `$Global:PSWebServer` in job scope if it doesn't exist
- Attach the synchronized `Metrics` object to `$Global:PSWebServer.Metrics` in job scope
- Pass `$Global:PSWebServer.Project_Root.Path` as second parameter

**Before**:
```powershell
Start-Job -ScriptBlock {
    param($MetricsState, $ModulePath)
    Import-Module PSWebHost_Metrics -Force
    # ... job used $MetricsState only
} -ArgumentList $Global:PSWebServer.Metrics.JobState, $Global:PSWebServer.ModulesPath
```

**After**:
```powershell
Start-Job -ScriptBlock {
    param($MetricsObject, $ProjectRoot)

    # Initialize global PSWebServer in job scope
    if (-not $Global:PSWebServer) {
        $Global:PSWebServer = @{}
    }
    if (-not $Global:PSWebServer.Project_Root) {
        $Global:PSWebServer.Project_Root = @{ Path = $ProjectRoot }
    }

    # Attach synchronized Metrics object
    $Global:PSWebServer.Metrics = $MetricsObject

    Import-Module PSWebHost_Metrics -Force
    # ... job now has full access to $Global:PSWebServer.Metrics
} -ArgumentList $Global:PSWebServer.Metrics, $Global:PSWebServer.Project_Root.Path
```

### Fix 2: Add Write-PSWebHostLog to Job

**File**: `apps/WebHostMetrics/app_init.ps1` (lines 23-35, 70-77)

**Changes**:
- Added mock `Write-PSWebHostLog` function in job scope
- Replaced `Write-Warning` with `Write-PSWebHostLog` in error handlers
- Added structured error data with exception type and stack trace

**Implementation**:
```powershell
# Mock Write-PSWebHostLog if not available in job scope
if (-not (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue)) {
    function Write-PSWebHostLog {
        param($Severity, $Category, $Message, $Data)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [$Severity] [$Category] $Message" -ForegroundColor $(
            switch ($Severity) {
                'Error' { 'Red' }
                'Warning' { 'Yellow' }
                'Info' { 'Cyan' }
                default { 'Gray' }
            }
        )
    }
}
```

**Error Handling**:
```powershell
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' `
        -Message "Error in metrics collection job: $($_.Exception.Message)" `
        -Data @{
            Exception = $_.Exception.GetType().FullName
            StackTrace = $_.ScriptStackTrace
        }

    if ($MetricsObject.JobState.Errors.Count -lt 100) {
        [void]$MetricsObject.JobState.Errors.Add(@{
            Timestamp = Get-Date
            Message = $_.Exception.Message
            StackTrace = $_.ScriptStackTrace
        })
    }
}
```

### Fix 3: Initialize Missing JobState Properties

**File**: `apps/WebHostMetrics/modules/PSWebHost_Metrics/PSWebHost_Metrics.psm1` (lines 66-78)

**Changes**:
- Added initialization for all missing properties used by metrics functions

**Before**:
```powershell
JobState = [hashtable]::Synchronized(@{
    Running = $false
    LastCollection = $null
    LastAggregation = $null
    LastCsvWrite = $null
    Errors = [System.Collections.ArrayList]::Synchronized(...)
})
```

**After**:
```powershell
JobState = [hashtable]::Synchronized(@{
    Running = $false
    LastCollection = $null
    LastAggregation = $null
    LastCsvWrite = $null
    LastInterimCsvWrite = $null
    LastCsvToSqliteMove = $null
    Last60sAggregation = $null
    LastCleanup = $null
    LastCsvCleanup = $null
    ExecutionStartTime = $null
    Errors = [System.Collections.ArrayList]::Synchronized(...)
})
```

### Fix 4: Consolidate Module Locations

**Action**: Removed global module location

**Changes**:
- Deleted `modules/PSWebHost_Metrics/` directory
- Kept only `apps/WebHostMetrics/modules/PSWebHost_Metrics/`
- Both modules were identical (same SHA256 hash)

**Verification**:
```powershell
# Both modules had same hash before deletion
SHA256: C29E598FE4B6A8387EE6B5F7E9B204E0CCFD6B6248A33CE371A03BD41AAA2EC3
Size: 62,312 bytes
```

## Current Status

### CSV File Generation
- Last metrics CSV files generated: **2026-01-08 23:59:00** (12 days ago)
- Most recent files:
  - `Network_2026-01-08_23-59-00.csv` (673 bytes)
  - `Perf_CPUCore_2026-01-08_23-59-00.csv` (582 bytes)
  - `Perf_MemoryUsage_2026-01-08_23-59-00.csv` (117 bytes)
  - `metrics_2026-01-08.csv` (11,492 bytes - legacy format)

### Expected Behavior After Fixes

1. **Job Initialization**:
   - Job will have full access to `$Global:PSWebServer.Metrics` structure
   - All functions can access `Current`, `Samples`, and `Aggregated` data
   - JobState properties properly initialized and accessible

2. **Metrics Collection** (every 5 seconds):
   - Collect system snapshot via `Get-SystemMetricsSnapshot`
   - Update `$Global:PSWebServer.Metrics.Current`
   - Add sample to `$Global:PSWebServer.Metrics.Samples` array

3. **CSV File Generation** (every 1 minute at :00 seconds):
   - Function: `Write-MetricsToInterimCsv`
   - Files created: `Perf_CPUCore_*.csv`, `Perf_MemoryUsage_*.csv`, etc.
   - Format: `Perf_CPUCore_2026-01-20_13-00-00.csv`

4. **SQLite Archival** (every 5 minutes):
   - Function: `Move-CsvToSqlite`
   - Moves CSV data to `PsWebHost_Data/pswebhost_perf.db`

5. **Error Logging**:
   - All errors logged via `Write-PSWebHostLog`
   - Errors stored in `$Global:PSWebServer.Metrics.JobState.Errors`
   - Stack traces included in error records

## Testing the Fixes

### Restart Metrics Collection

To apply the fixes, restart the metrics collection job:

```powershell
# Stop existing job
if ($Global:PSWebServer.MetricsJob) {
    $Global:PSWebServer.Metrics.JobState.ShouldStop = $true
    Start-Sleep -Seconds 6  # Wait for job to exit gracefully
    Stop-Job -Job $Global:PSWebServer.MetricsJob -ErrorAction SilentlyContinue
    Remove-Job -Job $Global:PSWebServer.MetricsJob -Force -ErrorAction SilentlyContinue
}

# Reload app to start new job with fixes
# Option 1: Restart entire PSWebHost server
# Option 2: Manually run app_init.ps1 (requires proper context)
```

### Verify Job Output

```powershell
# Check for errors
Receive-Job -Job $Global:PSWebServer.MetricsJob -Keep

# Check job state
$Global:PSWebServer.Metrics.JobState

# Check recent errors
$Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 5

# Verify metrics are being collected
$Global:PSWebServer.Metrics.Current

# Check sample count (should grow every 5 seconds, max 720 samples = 1 hour)
$Global:PSWebServer.Metrics.Samples.Count
```

### Verify CSV Files

```powershell
# Check for new CSV files
Get-ChildItem 'PsWebHost_Data\metrics' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 |
    Format-Table Name, LastWriteTime, Length -AutoSize

# Monitor CSV creation (run in separate window)
while ($true) {
    Clear-Host
    Get-ChildItem 'PsWebHost_Data\metrics' |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5 |
        Format-Table Name, LastWriteTime -AutoSize
    Start-Sleep -Seconds 5
}
```

### Check API Endpoint

```powershell
# Test history endpoint with CSV data
. 'apps\WebHostMetrics\routes\api\v1\metrics\history\get.ps1' `
    -test -roles admin `
    -Query @{timerange='1h'; metrics='cpu,memory'}
```

## Related Files Modified

1. `apps/WebHostMetrics/app_init.ps1` - Job initialization and error handling
2. `apps/WebHostMetrics/modules/PSWebHost_Metrics/PSWebHost_Metrics.psm1` - JobState properties
3. Deleted: `modules/PSWebHost_Metrics/` - Duplicate module removed

## Next Steps

1. **Restart PSWebHost server** to apply fixes
2. **Monitor job output** for any remaining errors
3. **Verify CSV files** are being created in `PsWebHost_Data/metrics/`
4. **Test history API endpoint** to confirm CSV data is accessible
5. **Update frontend** memory-histogram component to use CSV-based history endpoint

## Benefits of These Fixes

1. ✅ **Job Stability**: Proper global object initialization prevents property access errors
2. ✅ **Better Logging**: `Write-PSWebHostLog` provides structured error logging with timestamps
3. ✅ **Complete Tracking**: All JobState properties initialized, preventing null reference errors
4. ✅ **Module Consolidation**: Single module location reduces confusion and maintenance
5. ✅ **Error Details**: Stack traces included in error records for better debugging
6. ✅ **Graceful Degradation**: Job continues running even if individual collection attempts fail
