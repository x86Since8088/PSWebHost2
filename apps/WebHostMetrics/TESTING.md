# WebHostMetrics Testing Guide

**Last Updated**: 2026-02-23
**Version**: 1.0.0

---

## Overview

This document describes how to test the WebHostMetrics app, including unit tests, integration tests, and manual testing procedures.

---

## Test Structure

```
apps/WebHostMetrics/tests/
└── twin/                    # Twin test files (endpoint testing)
    └── (test files)
```

---

## Running Tests

### Prerequisites

1. PSWebHost server must be running
2. WebHostMetrics app must be enabled
3. Pester testing framework (if using Pester)

### Run All Tests

```powershell
# From project root
Invoke-Pester -Path apps/WebHostMetrics/tests/
```

### Run Specific Test Suite

```powershell
# Twin tests (endpoint tests)
Invoke-Pester -Path apps/WebHostMetrics/tests/twin/
```

---

## Manual Testing Procedures

### Test 1: Metrics Collection Job

**Purpose**: Verify background job is running and collecting metrics

**Steps**:
```powershell
# 1. Check job status
Get-Job -Name "PSWebHost_MetricsCollection"
# Expected: State = Running

# 2. Check recent metrics
$Global:PSWebServer.Metrics.Current
# Expected: Recent timestamp, valid CPU/memory data

# 3. Check sample count
$Global:PSWebServer.Metrics.Samples.Count
# Expected: Growing number (max 720 = 1 hour of 5s samples)

# 4. Check for errors
$Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 5
# Expected: Empty or minimal errors
```

**Expected Results**:
- Job shows "Running" state
- Current metrics have recent timestamp
- Sample count grows every 5 seconds
- No critical errors

---

### Test 2: CSV File Generation

**Purpose**: Verify CSV files are being created

**Steps**:
```powershell
# 1. Check for recent CSV files
Get-ChildItem "C:\SC\PsWebHost\PsWebHost_Data\metrics" -Filter "*.csv" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 |
    Format-Table Name, LastWriteTime, Length

# 2. Verify file naming convention
# Expected pattern: Perf_CPUCore_YYYY-MM-DD_HH-MM-SS.csv
```

**Expected Results**:
- CSV files created within last 5 minutes
- Files follow naming convention
- Multiple metric types present (CPU, Memory, Disk, Network)
- Files have non-zero size

---

### Test 3: API Endpoints

#### Test 3a: Current Metrics Endpoint

```powershell
# Test current metrics endpoint
. apps/WebHostMetrics/routes/api/v1/metrics/get.ps1 -test
```

**Expected Output**:
```json
{
  "status": "success",
  "timestamp": "<recent timestamp>",
  "hostname": "<server name>",
  "metrics": {
    "cpu": { ... },
    "memory": { ... },
    "disk": { ... },
    "network": { ... }
  }
}
```

#### Test 3b: History Endpoint

```powershell
# Test history endpoint with timerange
. apps/WebHostMetrics/routes/api/v1/metrics/history/get.ps1 -test -Query @{
    metric = 'cpu'
    timerange = '5m'
}
```

**Expected Output**:
```json
{
  "status": "success",
  "format": "csv",
  "sources": "Perf_CPUCore",
  "data": {
    "Perf_CPUCore": "Timestamp,Host,CoreNumber,Percent_Min,..."
  }
}
```

#### Test 3c: Server Heatmap UI Endpoint

```powershell
# Test server heatmap endpoint
. apps/WebHostMetrics/routes/cards/server-heatmap/get.ps1 -test
```

**Expected Output**:
```json
{
  "status": "success",
  "scriptPath": "/apps/WebHostMetrics/public/elements/server-heatmap/component.js",
  "element": { ... }
}
```

---

### Test 4: UI Component

**Purpose**: Verify dashboard component loads and displays data

**Steps**:
1. Open browser to `http://localhost:8080` (or your server URL)
2. Navigate to metrics dashboard
3. Verify component loads
4. Verify charts display
5. Verify auto-refresh works

**Expected Results**:
- Server heatmap component loads without errors
- CPU, memory, disk, network charts display
- Data updates every 5 seconds
- No JavaScript console errors

---

### Test 5: Data Retention

**Purpose**: Verify old data is cleaned up

**Steps**:
```powershell
# 1. Check oldest CSV file
Get-ChildItem "C:\SC\PsWebHost\PsWebHost_Data\metrics" -Filter "*.csv" |
    Sort-Object LastWriteTime |
    Select-Object -First 1 |
    Format-List Name, LastWriteTime

# 2. Calculate age
$oldest = Get-ChildItem "C:\SC\PsWebHost\PsWebHost_Data\metrics" -Filter "*.csv" |
    Sort-Object LastWriteTime |
    Select-Object -First 1
$age = (Get-Date) - $oldest.LastWriteTime
$age.Days

# Expected: Should be less than csvRetentionDays (default: 30)
```

**Expected Results**:
- Oldest file is within retention period (30 days)
- No files older than csvRetentionDays
- Cleanup happens automatically

---

### Test 6: Memory Bounds

**Purpose**: Verify in-memory storage doesn't grow indefinitely

**Steps**:
```powershell
# 1. Check sample count
$sampleCount = $Global:PSWebServer.Metrics.Samples.Count
Write-Host "Sample count: $sampleCount"

# Wait 5 minutes, check again
Start-Sleep -Seconds 300
$newSampleCount = $Global:PSWebServer.Metrics.Samples.Count
Write-Host "New sample count: $newSampleCount"

# 2. Check aggregated count
$aggCount = $Global:PSWebServer.Metrics.Aggregated.Count
Write-Host "Aggregated count: $aggCount"
```

**Expected Results**:
- Sample count stabilizes at ~720 (1 hour of 5s samples)
- Aggregated count stabilizes at ~1440 (24 hours of 1min aggregates)
- Counts don't grow indefinitely

---

## Performance Testing

### Test 7: API Response Times

**Purpose**: Measure endpoint performance

```powershell
# Test current metrics endpoint speed
Measure-Command {
    . apps/WebHostMetrics/routes/api/v1/metrics/get.ps1 -test
}

# Test history endpoint speed
Measure-Command {
    . apps/WebHostMetrics/routes/api/v1/metrics/history/get.ps1 -test -Query @{
        metric = 'cpu'
        timerange = '1h'
    }
}
```

**Expected Results**:
- Current metrics: < 500ms
- History (1h): < 1000ms
- History (24h): < 3000ms

---

### Test 8: Job CPU Usage

**Purpose**: Verify metrics job doesn't consume excessive CPU

```powershell
# Monitor job CPU usage
$job = Get-Job -Name "PSWebHost_MetricsCollection"
$process = Get-Process -Id $job.ChildJobs[0].State.ProcessId -ErrorAction SilentlyContinue

if ($process) {
    # Monitor for 1 minute
    1..12 | ForEach-Object {
        $cpu = $process.CPU
        Write-Host "CPU Time: $cpu seconds"
        Start-Sleep -Seconds 5
    }
}
```

**Expected Results**:
- CPU usage < 5% on average
- No runaway CPU consumption
- Stable over time

---

## Troubleshooting Test Failures

### Job Not Running

**Symptom**: `Get-Job` shows no job or job is stopped

**Fix**:
```powershell
# Restart metrics collection
. apps/WebHostMetrics/Restart-MetricsCollection.ps1 -Force
```

### No CSV Files Created

**Symptom**: No files in PsWebHost_Data/metrics/

**Check**:
1. Job is running (see above)
2. Directory exists and is writable
3. Check job errors: `$Global:PSWebServer.Metrics.JobState.Errors`

**Fix**:
```powershell
# Create directory if missing
New-Item -Path "PsWebHost_Data/metrics" -ItemType Directory -Force

# Restart job
. apps/WebHostMetrics/Restart-MetricsCollection.ps1 -Force
```

### API Endpoints Return Empty Data

**Symptom**: Endpoints return 200 OK but no metrics data

**Check**:
```powershell
# Verify metrics are being collected
$Global:PSWebServer.Metrics.Current
$Global:PSWebServer.Metrics.Samples.Count

# Check if module is loaded
Get-Module PSWebHost_Metrics
```

**Fix**:
```powershell
# Reload module
Import-Module apps/WebHostMetrics/modules/PSWebHost_Metrics/PSWebHost_Metrics.psm1 -Force

# Re-initialize
Initialize-PSWebMetrics
```

---

## Test Coverage

### Current Coverage

| Component | Coverage | Status |
|-----------|----------|--------|
| API Endpoints | Manual testing available | GOOD |
| Background Job | Manual testing available | GOOD |
| CSV Generation | Manual testing available | GOOD |
| UI Component | Manual browser testing | GOOD |
| Data Retention | Manual testing available | GOOD |
| Error Handling | Partial | NEEDS IMPROVEMENT |
| Edge Cases | Limited | NEEDS IMPROVEMENT |

### Coverage Goals

- Unit tests: 80% code coverage
- Integration tests: All API endpoints
- Performance tests: Response time benchmarks
- UI tests: Component rendering and interaction

---

## Automated Testing (Future)

### Planned Test Suites

1. **Pester Unit Tests**
   - Module function testing
   - Error handling verification
   - Data validation

2. **API Integration Tests**
   - Endpoint response validation
   - Authentication testing
   - Error response testing

3. **Performance Tests**
   - Response time benchmarking
   - Load testing
   - Memory leak detection

4. **UI Tests** (Selenium/Playwright)
   - Component loading
   - Chart rendering
   - User interaction

---

## CI/CD Integration

### GitHub Actions (Future)

```yaml
name: WebHostMetrics Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run Pester Tests
        shell: pwsh
        run: |
          Invoke-Pester -Path apps/WebHostMetrics/tests/ -OutputFormat NUnitXml -OutputFile TestResults.xml
      - name: Publish Test Results
        uses: EnricoMi/publish-unit-test-result-action@v1
        with:
          files: TestResults.xml
```

---

## Test Data

### Sample Metrics Response

```json
{
  "status": "success",
  "timestamp": "2026-02-23 14:30:00",
  "hostname": "SERVER01",
  "metrics": {
    "cpu": {
      "CoreCount": 8,
      "TotalPercent": 25.3,
      "AvgPercent": 24.8,
      "Cores": [22.1, 25.4, 26.8, 24.9, 23.5, 25.1, 24.2, 23.8]
    },
    "memory": {
      "TotalGB": 16.0,
      "UsedGB": 8.2,
      "FreeGB": 7.8,
      "PercentUsed": 51.3
    }
  }
}
```

---

## Best Practices

1. **Always test in isolated environment first**
2. **Monitor job errors during testing**
3. **Clean up test data after completion**
4. **Document any test failures**
5. **Run performance tests separately from functional tests**
6. **Test both success and failure scenarios**

---

## Test Checklist

Before releasing a new version:

- [ ] All manual tests pass
- [ ] API endpoints return valid data
- [ ] Background job runs without errors
- [ ] CSV files are created correctly
- [ ] UI component loads and displays data
- [ ] Data retention works correctly
- [ ] Memory usage is bounded
- [ ] Performance meets benchmarks
- [ ] No critical errors in logs

---

## Support

For test-related issues:
1. Check this testing guide
2. Review README.md troubleshooting section
3. Check ARCHITECTURE.md for technical details
4. Review job errors: `$Global:PSWebServer.Metrics.JobState.Errors`

---

**Document Status**: Active
**Maintained By**: WebHostMetrics Team
**Last Test Run**: Manual testing procedures verified 2026-02-23
